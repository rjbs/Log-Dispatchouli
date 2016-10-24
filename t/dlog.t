use strict;
use warnings;

use Log::Dispatchouli;
use Test::More 0.88;
use Test::Deep;

{
  my $logger = Log::Dispatchouli->new_tester({
    log_pid => 1,
    ident   => 't/basic.t',
  });

  isa_ok($logger, 'Log::Dispatchouli');

  is($logger->ident, 't/basic.t', '$logger->ident is available');

  is_deeply $logger->dlog([ "point: %s" ])->({x=>1,y=>2}) => {
      x=>1,y=>2
  }, "dlog pass through its arguments";

  is $logger->dlog_debug('this will not get logged')->() => undef,
    "nothing passed";

  cmp_deeply(
    $logger->events,
    [
      superhashof({
        message => re(qr/$$.+\Qpoint: {{{"x": 1,\E\s?\Q"y": 2}}}\E\z/)
      })
    ],
    "events with struts logged to self",
  );

  eval { $logger->log_fatal([ 'this is good: %s', [ 1, 2, 3 ] ]) };
  like($@, qr(good: \{\{\[), "log_fatal is fatal");
}

{
  my $logger = Log::Dispatchouli->new_tester({
    to_self   => 1,
    log_pid   => 0,
  });

  isa_ok($logger, 'Log::Dispatchouli');

  is_deeply $logger->dlog([ "point: %s" ])->({x=>1,y=>2}) => { x=>1, y=>2 }, "dlog pass information through";
  is $logger->dlog_debug('this will not get logged')->() => undef, "nothing to pass";

  cmp_deeply(
    $logger->events,
    [
      superhashof({
        message => code(sub { index($_[0], $$) == -1 }),
      })
    ],
    'events with struts logged to self (no $$)',
  );

  eval { $logger->log_fatal([ 'this is good: %s', [ 1, 2, 3 ] ]) };
  like($@, qr(good: \{\{\[), "log_fatal is fatal");
}

{
  my $logger = Log::Dispatchouli->new({
    ident   => 'foo',
    to_self => 1,
    log_pid => 0,
  });

  is $logger->dlog->('foo') => 'foo', "dlog passthrough";
  cmp_deeply($logger->events, [ superhashof({ message =>'foo' }) ], 'log foo');

  $logger->clear_events;
  cmp_deeply($logger->events, [ ], 'log empty after clear');

  is $logger->dlog('bar')->() => undef, "dlog, nothing passed";
  cmp_deeply($logger->events, [ superhashof({ message =>'bar' }) ], 'log bar');

  $logger->dlog('foo')->();
  cmp_deeply(
    $logger->events,
    [
      superhashof({ message =>'bar' }),
      superhashof({ message =>'foo' }),
    ],
    'log keeps accumulating',
  ) or diag explain $logger->events;
}

{
  my $logger = Log::Dispatchouli->new({
    ident   => 'foo',
    to_self => 1,
    log_pid => 0,
  });

  is_deeply $logger->dlog(sub { [ '%s %s', '[foo]', @_ ], '..' })->( [ qw/ foo /] ) 
    => [ 'foo' ], "dlog passthrough";

  is(
    $logger->events->[0]{message},
    '[foo] {{["foo"]}} ..',
    "multi-arg logging",
  );

  $logger->set_prefix('xyzzy: ');
  $logger->dlog->('foo');
  $logger->clear_prefix;
  $logger->dlog->('bar');

  is($logger->events->[1]{message}, 'xyzzy: foo', 'set a prefix');
  is($logger->events->[2]{message}, 'bar',        'clear prefix');
}

{
  my $logger = eval { Log::Dispatchouli->new; };
  like($@, qr/no ident specified/, "can't make a logger without ident");
}

{
  my $logger = Log::Dispatchouli->new({
    ident   => 'foo',
    to_self => 1,
    log_pid => 0,
  });

  $logger->dlog({ prefix => '[ALERT] ' })->("foo\nbar\nbaz");

  my $want_0 = <<'END_LOG';
[ALERT] foo
[ALERT] bar
[ALERT] baz
END_LOG

  chomp $want_0;

  $logger->dlog(
    {
      prefix => sub {
        my $m = shift;
        my @lines = split /\n/, $m;
        $lines[0] = "<<< $lines[0]";
        $lines[1] = "||| $lines[1]";
        $lines[2] = ">>> $lines[2]";

        return join "\n", @lines;
      },
    },
)->(
    "foo\nbar\nbaz",
  );

  my $want_1 = <<'END_LOG';
<<< foo
||| bar
>>> baz
END_LOG

  chomp $want_1;

  is(
    $logger->events->[0]{message},
    $want_0,
    "multi-line and prefix (string)",
  );

  is(
    $logger->events->[1]{message},
    $want_1,
    "multi-line and prefix (code)",
  );
}

{
  my $logger = Log::Dispatchouli->new_tester({ debug => 1 });

  $logger->dlog->('info');
  $logger->dlog->('debug');

  cmp_deeply(
    $logger->events,
    [
      superhashof({ message => 'info' }),
      superhashof({ message => 'debug' }),
    ],
    'info and debug while not muted',
  );

  $logger->clear_events;

  $logger->mute;

  $logger->dlog->('info');
  $logger->dlog->('debug');

  cmp_deeply($logger->events, [ ], 'nothing logged while muted');

  ok(
    ! eval { $logger->log_fatal('fatal'); 1},
    "log_fatal still dies while muted",
  );

  cmp_deeply(
    $logger->events,
    [ superhashof({ message => 'fatal' }) ],
    'logged a fatal even while muted'
  );
}

subtest "print and log different strings" => sub {
    my $logger = Log::Dispatchouli->new_tester({ debug => 1 });

    is $logger->dlog('foo')->('bar') => 'bar', "passthrough";

    cmp_deeply $logger->events, [
      superhashof({ message => 'foo' }),
    ], "logged";
};

done_testing;
