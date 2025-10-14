use v5.20;
use warnings;
package Log::Fmt;
# ABSTRACT: a little parser and emitter of structured log lines

use experimental 'postderef'; # Not dangerous.  Is accepted without changed.

use Encode ();
use Params::Util qw(_ARRAY0 _HASH0 _CODELIKE);
use Scalar::Util qw(refaddr);
use String::Flogger ();

=head1 OVERVIEW

This library primarily exists to service L<Log::Dispatchouli>'s C<log_event>
methods.  It converts an arrayref of key/value pairs to a string that a human
can scan tolerably well, and which a machine can parse about as well.  It can
also do that tolerably-okay parsing for you.

=head1 SPECIFICATION

=head2 The logfmt text format

Although quite a few tools exist for managing C<logfmt>, there is no spec-like
document for it.  Because you may require multiple implementations, a
specification can be helpful.

Every logfmt event is a sequence of pairs in the form C<key=value>.  Pairs are
separated by a single space.

    event = pair *(WSP pair)
    pair  = key "=" value
    okchr = %x21 / %x23-3c / %x3e-5b / %x5d-7e ; VCHAR minus \ and " and =
    key   = 1*(okchr)
    value = key / quoted

    quoted = DQUOTE *( escaped / quoted-ok / okchr / eightbit ) DQUOTE
    escaped         = escaped-special / escaped-hex
    escaped-special = "\\" / "\n" / "\r" / "\t" / ("\" DQUOTE)
    escaped-hex     = "\x{" 2HEXDIG "}" ; lowercase forms okay also
    quoted-ok       = SP / "="
    eightbit        = %x80-ff

When formatting a value, if a value is already a valid C<key> token, use it
without further quoting.

=head2 Quoting a Unicode string

It is preferable to build quoted values from a Unicode string, because it's
possible to know whether a given codepoint is a non-ASCII unsafe character,
like C<LINE SEPARATOR>.  Safe non-ASCII characters can be directly UTF-8
encoded, rather than quoted with C<\x{...}>.  In that way, viewing logfmt events
with a standard terminal can show something like:

    user.name="Jürgen"

To generate a C<quoted> from a Unicode string, for each codepoint:

=begin :list

* convert C<\> to C<\\>
* convert C<"> to C<\">
* convert a newline (U+000A) to C<\n>
* convert a carriage return (U+000D) to C<\r>
* convert a character tabulation (U+0009) to C<\t>
* for any control character (by general category) or vertical newline:

=begin :list

* encode the character into a UTF-8 bytestring
* convert each byte in the bytestring into C<\x{...}> form
* use that sequence of C<\x{...}> codes in place of the replaced character

=end :list

=end :list

Finally, UTF-8 encode the entire string and wrap it in double qoutes.

B<This Perl implementation assumes that all string values to be encoded are
character strings!>

=head3 Quoting a bytestring

Encoding a Unicode string is preferable, but may not be practical.  In those
cases when you have only a byte sequence, apply these steps.

For each byte (using ASCII conventions):

=for :list
* convert C<\> to C<\\>
* convert C<"> to C<\">
* convert a newline (C<%0a>) to C<\n>
* convert a carriage return (C<%0d>) to C<\r>
* convert a character tabulation (C<%x09>) to C<\t>
* convert any control character (C<%x00-1f / %x7f>) to the C<\x{...}> form
* convert any non-ASCII byte (C<%x80-ff>) to the C<\x{...}> form

Finally, wrap the string in double quotes.

=cut

=method format_event_string

  my $octets = Log::Fmt->format_event_string([
    key1 => $value1,
    key2 => $value2,
  ]);

Note especially that if any value to encode is a reference I<to a reference>,
then String::Flogger is used to encode the referenced value.  This means you
can embed, in your logfmt, a JSON dump of a structure by passing a reference to
the structure, instead of passing the structure itself.

String values are assumed to be character strings, and will be UTF-8 encoded as
part of the formatting process.

=cut

# okchr = %x21 / %x23-3c / %x3e-5b / %x5d-7e ; VCHAR minus \ and " and =
# key   = 1*(okchr)
# value = key / quoted
my $KEY_RE = qr{[\x21\x23-\x3c\x3e-\x5b\x5d-\x7e]+};

sub _escape_unprintable {
  my ($chr) = @_;

  return join q{},
    map {; sprintf '\\x{%02x}', ord }
    split //, Encode::encode('utf-8', $chr, Encode::FB_DEFAULT);
}

sub _quote_string {
  my ($string) = @_;

  $string =~ s{\\}{\\\\}g;
  $string =~ s{"}{\\"}g;
  $string =~ s{\x09}{\\t}g;
  $string =~ s{\x0A}{\\n}g;
  $string =~ s{\x0D}{\\r}g;
  $string =~ s{([\pC\v])}{_escape_unprintable($1)}ge;

  $string = Encode::encode('utf-8', $string, Encode::FB_DEFAULT);

  return qq{"$string"};
}

sub string_flogger { 'String::Flogger' }

sub _pairs_to_kvstr_aref {
  my ($self, $aref, $seen, $prefix) = @_;

  $seen //= {};

  my @kvstrs;

  KEY: for (my $i = 0; $i < @$aref; $i += 2) {
    # replace non-ident-safe chars with ?
    my $key = length $aref->[$i] ? "$aref->[$i]" : '~';
    $key =~ tr/\x21\x23-\x3C\x3E-\x7E/?/c;

    # If the prefix is "" you can end up with a pair like ".foo=1" which is
    # weird but probably best.  And that means you could end up with
    # "foo..bar=1" which is also weird, but still probably for the best.
    $key = "$prefix.$key" if defined $prefix;

    my $value = $aref->[$i+1];

    if (_CODELIKE $value) {
      $value = $value->();
    }

    if (ref $value && ref $value eq 'REF') {
      $value = $self->string_flogger->flog([ '%s', $$value ]);
    }

    if (! defined $value) {
      $value = '~missing~';
    } elsif (ref $value) {
      my $refaddr = refaddr $value;

      if ($seen->{ $refaddr }) {
        $value = $seen->{ $refaddr };
      } elsif (_ARRAY0($value)) {
        $seen->{ $refaddr } = "&$key";

        push @kvstrs, $self->_pairs_to_kvstr_aref(
          [ map {; $_ => $value->[$_] } (0 .. $#$value) ],
          $seen,
          $key,
        )->@*;

        next KEY;
      } elsif (_HASH0($value)) {
        $seen->{ $refaddr } = "&$key";

        push @kvstrs, $self->_pairs_to_kvstr_aref(
          [ $value->%{ sort keys %$value } ],
          $seen,
          $key,
        )->@*;

        next KEY;
      } else {
        $value = "$value"; # Meh.
      }
    }

    my $str = "$key="
            . ($value =~ /\A$KEY_RE\z/
               ? "$value"
               : _quote_string($value));

    push @kvstrs, $str;
  }

  return \@kvstrs;
}

sub format_event_string {
  my ($self, $aref) = @_;

  return join q{ }, $self->_pairs_to_kvstr_aref($aref)->@*;
}

=method parse_event_string

  my $kv_pairs = Log::Fmt->parse_event_string($octets);

Given the kind of (byte) string emitted by C<format_event_string>, this method
returns a reference to an array of key/value pairs.  After being unquoted,
value strings will be UTF-8 decoded into character strings.

This isn't exactly a round trip.  First off, the formatting can change illegal
keys by replacing characters with question marks, or replacing empty strings
with tildes.  Secondly, the formatter will expand some values like arrayrefs
and hashrefs into multiple keys, but the parser will not recombined those keys
into structures.  Also, there might be other asymmetric conversions.  That
said, the string escaping done by the formatter should correctly reverse.

If the input string is badly formed, hunks that don't appear to be value
key/value pairs will be presented as values for the key C<junk>.

=cut

sub parse_event_string {
  my ($self, $octets) = @_;

  my @result;

  HUNK: while (length $octets) {
    if ($octets =~ s/\A($KEY_RE)=($KEY_RE)(?:\s+|\z)//) {
      push @result, $1, $2;
      next HUNK;
    }

    if ($octets =~ s/\A($KEY_RE)="((\\\\|\\"|[^"])*?)"(?:\s+|\z)//) {
      my $key = $1;
      my $qstring = $2;

      $qstring =~ s{
        ( \\\\ | \\["nrt] | (\\x)\{([[:xdigit:]]{2})\} )
      }
      {
          $1 eq "\\\\"        ? "\\"
        : $1 eq "\\\""        ? q{"}
        : $1 eq "\\n"         ? qq{\n}
        : $1 eq "\\r"         ? qq{\r}
        : $1 eq "\\t"         ? qq{\t}
        : ($2//'') eq "\\x"   ? chr(hex("0x$3"))
        :                       $1
      }gex;

      push @result, $key, Encode::decode('utf-8', $qstring, Encode::FB_DEFAULT);
      next HUNK;
    }

    if ($octets =~ s/\A(\S+)(?:\s+|\z)//) {
      push @result, 'junk', $1;
      next HUNK;
    }

    # I hope this is unreachable. -- rjbs, 2022-11-03
    push (@result, 'junk', $octets, aborted => 1);
    last HUNK;
  }

  return \@result;
}

=method parse_event_string_as_hash

    my $hashref = Log::Fmt->parse_event_string_as_hash($line);

This parses the given line as logfmt, then puts the key/value pairs into a hash
and returns a reference to it.

Because nothing prevents a single key from appearing more than once, you should
use this with the understanding that data could be lost.  No guarantee is made
of which value will be preserved.

=cut

sub parse_event_string_as_hash {
  my ($self, $octets) = @_;

  return { $self->parse_event_string($octets)->@* };
}

1;
