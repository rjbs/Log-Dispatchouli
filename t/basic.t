use strict;
use warnings;

use Log::Dispatchouli;
use Test::More 0.88;
use Test::Deep;

{
  my $logger = Log::Dispatchouli->new_tester({ to_self => 1 });

  isa_ok($logger, 'Log::Dispatchouli');

  $logger->log([ "point: %s", {x=>1,y=>2} ]);
  $logger->log_debug('this will not get logged');

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

  $logger->log([ "point: %s", {x=>1,y=>2} ]);
  $logger->log_debug('this will not get logged');

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

  $logger->log('foo');
  cmp_deeply($logger->events, [ superhashof({ message =>'foo' }) ], 'log foo');

  $logger->clear_events;
  cmp_deeply($logger->events, [ ], 'log empty after clear');

  $logger->log('bar');
  cmp_deeply($logger->events, [ superhashof({ message =>'bar' }) ], 'log bar');

  $logger->log('foo');
  cmp_deeply(
    $logger->events,
    [
      superhashof({ message =>'bar' }),
      superhashof({ message =>'foo' }),
    ],
    'log keeps accumulating',
  );
}

{
  my $logger = Log::Dispatchouli->new({
    ident   => 'foo',
    to_self => 1,
    log_pid => 0,
  });

  $logger->log([ '%s %s', '[foo]', [qw(foo)] ], "..");

  is(
    $logger->events->[0]{message},
    '[foo] {{["foo"]}} ..',
    "multi-arg logging",
  );

  $logger->set_prefix('xyzzy');
  $logger->log('foo');
  $logger->unset_prefix;
  $logger->log('bar');

  is($logger->events->[1]{message}, 'xyzzy: foo', 'set a prefix');
  is($logger->events->[2]{message}, 'bar',        'unset prefix');
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

  $logger->log({ prefix => '[ALERT] ' }, "foo\nbar\nbaz");

  my $want_0 = <<'END_LOG';
[ALERT] foo
[ALERT] bar
[ALERT] baz
END_LOG

  chomp $want_0;

  $logger->log(
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

done_testing;
