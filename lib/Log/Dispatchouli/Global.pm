use strict;
use warnings;
package Log::Dispatchouli::Global;
# ABSTRACT: a system for sharing a global, dynamically-scoped logger

use Carp ();
use Log::Dispatchouli;
use Scalar::Util ();

use Sub::Exporter::GlobExporter qw(glob_exporter);
use Sub::Exporter -setup => {
  collectors => {
    '$Logger' => glob_exporter(Logger => \'_build_logger'),
  },
};

=head1 DESCRIPTION

Log::Dispatchouli::Global is a framework for a global logger object. In your
top-level programs that are actually executed, you'd add something like this:

  use Log::Dispatchouli::Global '$Logger' => {
    init => {
      ident     => 'My::Daemon',
      facility  => 'local2',
      to_stdout => 1,
    },
  };

This will import a C<$Logger> into your program, and more importantly will
initialize it with a new L<Log::Dispatchouli> object created by passing the
value for the C<init> parameter to Log::Dispatchouli's C<new> method.

Much of the rest of your program, across various libraries, can then just use
this:

  use Log::Dispatchouli::Global '$Logger';

  sub whatever {
    ...

    $Logger->log("about to do something");

    local $Logger = $Logger->proxy({ proxy_prefix => "whatever: " });

    for (@things) {
      $Logger->log([ "doing thing %s", $_ ]);
      ...
    }
  }

This eliminates the need to pass around what is effectively a global, while
still allowing it to be specialized withing certain contexts of your program.

B<Warning!>  Although you I<could> just use Log::Dispatchouli::Global as your
shared logging library, you almost I<certainly> want to write a subclass that
will only be shared amongst your application's classes.
Log::Dispatchouli::Global is meant to be subclassed and shared only within
controlled systems.  Remember, I<sharing your state with code you don't
control is dangerous>.

=head1 USING

In general, you will either be using a Log::Dispatchouli::Global class to get
a C<$Logger> or to initialize it (and then get C<$Logger>).  These are both
demonstrated above.  Also, when importing C<$Logger> you may request it be
imported under a different name:

  use Log::Dispatchouli::Global '$Logger' => { -as => 'L' };

  $L->log( ... );

There is only one class method that you are likely to use: C<current_logger>.
This provides the value of the shared logger from the caller's context,
initializing it to a default if needed.  Even this method is unlikely to be
required frequently, but it I<does> allow users to I<see> C<$Logger> without
importing it.

=head1 SUBCLASSING

Before using Log::Dispatchouli::Global in your application, you should subclass
it.  When you subclass it, you should provide the following methods:

=head2 logger_globref

This method should return a globref in which the shared logger will be stored.
Subclasses will be in their own package, so barring any need for cleverness,
every implementation of this method can look like the following:

  sub logger_globref { no warnings 'once'; return \*Logger }

=cut

sub logger_globref {
  no warnings 'once';
  \*Logger;
}

sub current_logger {
  my ($self) = @_;

  my $globref = $self->logger_globref;

  unless (defined $$$globref) {
    $$$globref = $self->default_logger;
  }

  return $$$globref;
}

=head2 default_logger

If no logger has been initialized, but something tries to log, it gets the
default logger, created by calling this method.

The default implementation calls C<new> on the C<default_logger_class> with the
result of C<default_logger_args> as the arguments.

=cut

my $default_logger;
sub default_logger {
  my ($self) = @_;

  $default_logger ||= $self->default_logger_class->new(
    $self->default_logger_args
  );
}

=head2 default_logger_class

This returns the class on which C<new> will be called when initializing a
logger, either from the C<init> argument when importing or the default logger.

Its default value is Log::Dispatchouli.

=cut

sub default_logger_class { 'Log::Dispatchouli' }

=head2 default_logger_args

If no logger has been initialized, but something tries to log, it gets the
default logger, created by calling C<new> on the C<default_logger_class> and
passing the results of calling this method.

Its default return value creates a sink, so that anything logged without an
initialized logger is lost.

=cut

sub default_logger_args {
  return {
    ident     => "default/$0",
    facility  => undef,
  }
}

sub _build_logger {
  my ($self, $arg) = @_;

  my $globref = $self->logger_globref;
  my $default = $self->default_logger;

  my $Logger  = $$$globref;

  if ($arg and $arg->{init}) {
    if (
      $Logger
      and
      Scalar::Util::refaddr($Logger) != Scalar::Util::refaddr($default)
    ) {
      Carp::confess("attempted to initialize $self logger twice");
    }

    $$$globref = $self->default_logger_class->new($arg->{init});
  } else {
    $$$globref ||= $default;
  }

  return $globref;
}

1;
