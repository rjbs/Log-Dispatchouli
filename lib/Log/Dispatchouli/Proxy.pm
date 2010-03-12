use strict;
use warnings;
package Log::Dispatchouli::Proxy;
# ABSTRACT: a simple wrapper around Log::Dispatch

use Params::Util qw(_ARRAY0 _HASH0);

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
sub unset_prefix { undef $_[0]{prefix} }

sub set_debug    { $_[0]{debug} = $_[1] ? 1 : 0 }
sub get_debug    { return $_[0]{debug} }
sub clear_debug  { undef $_[0]{debug} }

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
