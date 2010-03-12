use strict;
use warnings;
package Log::Dispatchouli::Proxy;
# ABSTRACT: a simple wrapper around Log::Dispatch

use Params::Util qw(_ARRAY0 _HASH0);

=head1 DESCRIPTION

A Log::Dispatchouli::Proxy object is the child of a L<Log::Dispatchouli> logger
(or another proxy) and relays log messages to its parent.  It behaves almost
identically to a Log::Dispatchouli logger, and you should refer there for more
of its documentation.

Here are the differences:

=begin :list

* You can't create a proxy with C<< ->new >>, only by calling C<< ->proxy >> on an existing logger or proxy.

* C<set_debug> will set a value for the proxy; if none is set, C<get_debug> will check the parent's setting; C<clear_debug> will clear any set value on this proxy

* C<log_debug> messages will be redispatched to C<log> (bug to the 'debug' logging level) to prevent parent loggers from dropping them due to C<debug> setting differences

=end :list

=cut

sub _new {
  my ($class, $arg) = @_;

  my $guts = {
    parent => $arg->{parent},
    logger => $arg->{logger},
    debug  => $arg->{debug},
    proxy_prefix => $arg->{proxy_prefix},
  };

  bless $guts => $class;
}

sub proxy  {
  my ($self, $arg) = @_;
  $arg ||= {};

  (ref $self)->_new({
    parent => $self,
    logger => $self->logger,
    debug  => $arg->{debug},
    proxy_prefix => $arg->{proxy_prefix},
  });
}

sub parent { $_[0]{parent} }
sub logger { $_[0]{logger} }

sub set_prefix   { $_[0]{prefix} = $_[1] }
sub get_prefix   { $_[0]{prefix} }
sub clear_prefix { undef $_[0]{prefix} }
sub unset_prefix { $_[0]->clear_prefix }

sub set_debug    { $_[0]{debug} = $_[1] ? 1 : 0 }
sub clear_debug  { undef $_[0]{debug} }

sub get_debug {
  return $_[0]{debug} if defined $_[0]{debug};
  return $_[0]->parent->get_debug;
}

sub _get_all_prefix {
  my ($self, $arg) = @_;

  return [
    $self->{proxy_prefix},
    $self->get_prefix,
    _ARRAY0($arg->{prefix}) ? @{ $arg->{prefix} } : $arg->{prefix}
  ];
}

sub log {
  my ($self, @rest) = @_;
  my $arg = _HASH0($rest[0]) ? shift(@rest) : {};
  local $arg->{prefix} = $self->_get_all_prefix($arg);

  $self->parent->log($arg, @rest);
}

sub log_fatal {
  my ($self, @rest) = @_;

  my $arg = _HASH0($rest[0]) ? shift(@rest) : {};
  local $arg->{prefix} = $self->_get_all_prefix($arg);

  $self->parent->log_fatal($arg, @rest);
}

sub log_debug {
  my ($self, @rest) = @_;

  my $debug = $self->get_debug;
  return if defined $debug and ! $debug;

  my $arg = _HASH0($rest[0]) ? shift(@rest) : {};
  local $arg->{prefix} = $self->_get_all_prefix($arg);

  if ($debug) {
    local $arg->{level} = 'debug';
    $self->parent->log($arg, @rest);
    return;
  }

  $self->parent->log_debug($arg, @rest);
}

1;
