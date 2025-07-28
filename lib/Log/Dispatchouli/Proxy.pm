use v5.20;
use warnings;
package Log::Dispatchouli::Proxy;
# ABSTRACT: a simple wrapper around Log::Dispatch

# Not dangerous.  Accepted without change.
use experimental 'postderef', 'signatures';

use Log::Fmt ();
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

* C<log_debug> messages will be redispatched to C<log> (to the 'debug' logging level) to prevent parent loggers from dropping them due to C<debug> setting differences

=end :list

=cut

sub _new ($class, $arg) {
  my $guts = {
    parent => $arg->{parent},
    logger => $arg->{logger},
    debug  => $arg->{debug},
    proxy_prefix => $arg->{proxy_prefix},
    proxy_ctx    => $arg->{proxy_ctx},
  };

  bless $guts => $class;
}

sub proxy ($self, $arg = undef) {
  $arg ||= {};

  my @proxy_ctx;

  if (my $ctx = $arg->{proxy_ctx}) {
    @proxy_ctx = _ARRAY0($ctx)
               ? (@proxy_ctx, @$ctx)
               : (@proxy_ctx, $ctx->%{ sort keys %$ctx });
  }

  my $prox = (ref $self)->_new({
    parent => $self,
    logger => $self->logger,
    debug  => $arg->{debug},
    muted  => $arg->{muted},
    proxy_prefix => $arg->{proxy_prefix},
    proxy_ctx    => \@proxy_ctx,
  });
}

sub parent ($self) { $self->{parent} }
sub logger ($self) { $self->{logger} }

sub ident     ($self) { $self->{logger}->ident }
sub config_id ($self) { $self->{logger}->config_id }

sub get_prefix   ($self)          { $self->{prefix} }
sub set_prefix   ($self, $prefix) { $self->{prefix} = $prefix }
sub clear_prefix ($self)          { undef $self->{prefix} }
sub unset_prefix ($self)          { $self->clear_prefix }

sub set_debug    ($self, $bool) { $self->{debug} = $bool ? 1 : 0 }
sub clear_debug  ($self)        { undef $self->{debug} }

sub get_debug ($self) {
  return $self->{debug} if defined $self->{debug};
  return $self->parent->get_debug;
}

sub is_debug ($self) { $self->get_debug }
sub is_info  ($) { 1 }
sub is_fatal ($) { 1 }

sub mute   ($self) { $self->{muted} = 1 }
sub unmute ($self) { $self->{muted} = 0 }

sub set_muted   ($self, $bool) { $self->{muted} = $bool ? 1 : 0 }
sub clear_muted ($self)        { undef $self->{muted} }

sub _get_local_muted ($self) { $self->{muted} }

sub get_muted ($self) {
  return $self->{muted} if defined $self->{muted};
  return $self->parent->get_muted;
}

sub _get_all_prefix ($self, $arg) {
  return [
    $self->{proxy_prefix},
    $self->get_prefix,
    _ARRAY0($arg->{prefix}) ? @{ $arg->{prefix} } : $arg->{prefix}
  ];
}

sub flog_messages ($self, @rest) {
  my $arg = _HASH0($rest[0]) ? shift(@rest) : {};
  local $arg->{prefix} = $self->_get_all_prefix($arg);

  $self->parent->flog_messages($arg, @rest);
}

sub log ($self, @rest) {
  my $arg = _HASH0($rest[0]) ? shift(@rest) : {};

  return if $self->_get_local_muted and ! $arg->{fatal};

  local $arg->{prefix} = $self->_get_all_prefix($arg);

  $self->parent->log($arg, @rest);
}

sub log_fatal ($self, @rest) {
  my $arg = _HASH0($rest[0]) ? shift(@rest) : {};
  local $arg->{fatal}  = 1;

  $self->log($arg, @rest);
}

sub log_debug ($self, @rest) {
  my $debug = $self->get_debug;
  return if defined $debug and ! $debug;

  my $arg = _HASH0($rest[0]) ? shift(@rest) : {};
  local $arg->{level} = 'debug';

  $self->log($arg, @rest);
}

sub _compute_proxy_ctx_kvstr_aref ($self) {
  return $self->{proxy_ctx_kvstr} //= do {
    my @kvstr = $self->parent->_compute_proxy_ctx_kvstr_aref->@*;

    if ($self->{proxy_ctx}) {
      my $our_kv = Log::Fmt->_pairs_to_kvstr_aref($self->{proxy_ctx});
      push @kvstr, @$our_kv;
    }

    \@kvstr;
  };
}

sub fmt_event ($self, $type, $data) {
  my $kv_aref = Log::Fmt->_pairs_to_kvstr_aref([
    event => $type,
    (_ARRAY0($data) ? @$data : $data->%{ sort keys %$data })
  ]);

  splice @$kv_aref, 1, 0, $self->_compute_proxy_ctx_kvstr_aref->@*;

  return join q{ }, @$kv_aref;
}

sub log_event ($self, $event, $data) {
  return if $self->get_muted;

  my $message = $self->fmt_event($event, $data);

  $self->logger->dispatcher->log(
    level   => 'info',
    message => $message,
  );
}

sub log_debug_event ($self, $event, $data) {
  return unless $self->get_debug;

  return $self->log_event($event, $data);
}

sub info  ($self, @rest) { $self->log(@rest); }
sub fatal ($self, @rest) { $self->log_fatal(@rest); }
sub debug ($self, @rest) { $self->log_debug(@rest); }

use overload
  '&{}'    => sub { my ($self) = @_; sub { $self->log(@_) } },
  fallback => 1,
;

1;
