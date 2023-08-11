use v5.20;
use warnings;
package Log::Fmt;
# ABSTRACT: a little parser and emitter of structured log lines

use experimental 'postderef'; # Not dangerous.  Is accepted without changed.

use Params::Util qw(_ARRAY0 _HASH0 _CODELIKE);
use Scalar::Util qw(refaddr);

=head1 OVERVIEW

This library primarily exists to service L<Log::Dispatchouli>'s C<log_event>
methods.  It converts an arrayref of key/value pairs to a string that a human
can scan tolerably well, and which a machine can parse about as well.  It can
also do that tolerably-okay parsing for you.

=cut

=method format_event_string

  my $string = Log::Fmt->format_event_string([
    key1 => $value1,
    key2 => $value2,
  ]);

Note especially that if any value to encode is a reference I<to a reference>,
then String::Flogger is used to encode the referenced value.  This means you
can embed, in your logfmt, a JSON dump of a structure by passing a reference to
the structure, instead of passing the structure itself.

=cut

# ASCII after SPACE but excluding = and "
my $IDENT_RE = qr{[\x21\x23-\x3C\x3E-\x7E]+};

sub _quote_string {
  my ($string) = @_;

  $string =~ s{\\}{\\\\}g;
  $string =~ s{"}{\\"}g;
  $string =~ s{\x0A}{\\n}g;
  $string =~ s{\x0D}{\\r}g;
  $string =~ s{([\pC\v])}{sprintf '\\x{%x}', ord $1}ge;

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
            . ($value =~ /\A$IDENT_RE\z/
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

  my $kv_pairs = Log::Fmt->parse_event_string($string);

Given the kind of string emitted by C<format_event_string>, this method returns
a reference to an array of key/value pairs.

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
  my ($self, $string) = @_;

  my @result;

  HUNK: while (length $string) {
    if ($string =~ s/\A($IDENT_RE)=($IDENT_RE)(?:\s+|\z)//) {
      push @result, $1, $2;
      next HUNK;
    }

    if ($string =~ s/\A($IDENT_RE)="((\\\\|\\"|[^"])*?)"(?:\s+|\z)//) {
      my $key = $1;
      my $qstring = $2;

      $qstring =~ s{
        ( \\\\ | \\["nr] | (\\x)\{([[:xdigit:]]{1,5})\} )
      }
      {
          $1 eq "\\\\"        ? "\\"
        : $1 eq "\\\""        ? q{"}
        : $1 eq "\\n"         ? qq{\n}
        : $1 eq "\\r"         ? qq{\r}
        : ($2//'') eq "\\x"   ? chr(hex("0x$3"))
        :                       $1
      }gex;

      push @result, $key, $qstring; # TODO: do unescaping here
      next HUNK;
    }

    if ($string =~ s/\A(\S+)(?:\s+|\z)//) {
      push @result, 'junk', $1;
      next HUNK;
    }

    # I hope this is unreachable. -- rjbs, 2022-11-03
    push (@result, 'junk', $string, aborted => 1);
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
  my ($self, $string) = @_;

  return { $self->parse_event_string($string)->@* };
}

1;
