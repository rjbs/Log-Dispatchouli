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

  $logger->log([ '%s %s', '[foo]', [qw(foo)] ], "..");

  is(
    $logger->events->[0]{message},
    '[foo] {{["foo"]}} ..',
    "multi-arg logging",
  );
}

done_testing;
