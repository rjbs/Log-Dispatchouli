use strict;
use warnings;

use JSON::MaybeXS;
use Log::Dispatchouli;
use Test::More 0.88;
use Test::Deep;

sub event_logs_ok {
  my ($event_type, $data, $line, $desc) = @_;

  local $Test::Builder::Level = $Test::Builder::Level+1;

  my $logger = Log::Dispatchouli->new_tester({
    log_pid => 0,
    ident   => 't/basic.t',
  });

  $logger->log_event($event_type, $data);

  messages_ok($logger, [$line], $desc);
}

sub messages_ok {
  my ($logger, $lines, $desc) = @_;

  local $Test::Builder::Level = $Test::Builder::Level+1;

  my @messages = map {; $_->{message} } $logger->events->@*;

  my $ok = cmp_deeply(
    \@messages,
    $lines,
    $desc,
  );

  $logger->clear_events;

  unless ($ok) {
    diag "GOT: $_" for @messages;
  }

  return $ok;
}

sub logger_trio {
  my $logger = Log::Dispatchouli->new_tester({
    log_pid => 0,
    ident   => 't/basic.t',
  });

  my $proxy1 = $logger->proxy({ proxy_ctx => { 'inner' => 'proxy' } });
  my $proxy2 = $proxy1->proxy({ proxy_ctx => { 'outer' => 'proxy' } });

  return ($logger, $proxy1, $proxy2);
}

subtest "very basic stuff" => sub {
  event_logs_ok(
    'world-series' => [ phl => 1, hou => 0, games => [ 'done', 'in-progress' ] ],
    'event=world-series phl=1 hou=0 games.0=done games.1=in-progress',
    "basic data with an arrayref value",
  );

  event_logs_ok(
    'programmer-sleepiness' => {
      weary   => 8.62,
      excited => 3.2,
      motto   => q{Never say "never" ever again.},
    },
    'event=programmer-sleepiness excited=3.2 motto="Never say \\"never\\" ever again." weary=8.62',
    "basic data as a hashref",
  );

  event_logs_ok(
    'rich-structure' => [
      array => [
        { name => [ qw(Ricardo Signes) ], limbs => { arms => 2, legs => 2 } },
        [ 2, 4, 6 ],
      ],
    ],
    join(q{ }, qw(
      event=rich-structure
      array.0.limbs.arms=2
      array.0.limbs.legs=2
      array.0.name.0=Ricardo
      array.0.name.1=Signes
      array.1.0=2
      array.1.1=4
      array.1.2=6
    )),
    "a structured nested a few levels",
  );

  event_logs_ok(
    'empty-key' => { '' => 'disgusting' },
    'event=empty-key ~=disgusting',
    "cope with jerks putting empty keys into the data structure",
  );

  event_logs_ok(
    'bogus-subkey' => { valid => { 'foo bar' => 'revolting' } },
    'event=bogus-subkey valid.foo?bar=revolting',
    "cope with bogus key characters in recursion",
  );
};

subtest "very basic proxy operation" => sub {
  my ($logger, $proxy1, $proxy2) = logger_trio();

  $proxy2->log_event(pie_picnic => [
    pies_eaten => 1.2,
    joy_harvested => 6,
  ]);

  messages_ok(
    $logger,
    [
      'event=pie_picnic inner=proxy outer=proxy pies_eaten=1.2 joy_harvested=6'
    ],
    'got the expected log output from events',
  );
};

subtest "debugging in the proxies" => sub {
  my ($logger, $proxy1, $proxy2) = logger_trio();

  $proxy1->set_debug(1);

  $logger->log_debug_event(0 => [ seq => 0 ]);
  $proxy1->log_debug_event(1 => [ seq => 1 ]);
  $proxy2->log_debug_event(2 => [ seq => 2 ]);

  $proxy2->set_debug(0);

  $logger->log_debug_event(0 => [ seq => 3 ]);
  $proxy1->log_debug_event(1 => [ seq => 4 ]);
  $proxy2->log_debug_event(2 => [ seq => 5 ]);

  messages_ok(
    $logger,
    [
      # 'event=0 seq=0',                          # not logged, debugging
      'event=1 inner=proxy seq=1',
      'event=2 inner=proxy outer=proxy seq=2',
      # 'event=0 seq=3',                          # not logged, debugging
      'event=1 inner=proxy seq=4',
      # 'event=2 inner=proxy outer=proxy seq=5',  # not logged, debugging
    ],
    'got the expected log output from events',
  );
};

# NOT TESTED HERE:  "mute" and "unmute", which rjbs believes are probably
# broken already.  Their tests don't appear to test the important case of "root
# logger muted, proxy explicitly unmuted".

subtest "recursive structure" => sub {
  my ($logger, $proxy1, $proxy2) = logger_trio();

  my $struct = {};

  $struct->{recurse} = $struct;

  $logger->log_event('recursive-thing' => [ recursive => $struct ]);

  messages_ok(
    $logger,
    [
      'event=recursive-thing recursive.recurse=&recursive',
    ],
    "an event with recursive stuff terminates",
  );
};

subtest "reused JSON booleans" => sub {
  # It's not that this is extremely special, but we mostly don't want to
  # recurse into the same reference value multiple times, but we also don't
  # want the infuriating "reused boolean variable" you get from Dumper.  This
  # is just to make sure I don't accidentally break this case.
  my ($logger, $proxy1, $proxy2) = logger_trio();

  my $struct = {
    b => [ JSON::MaybeXS::true(), JSON::MaybeXS::false() ],
    f => [ (JSON::MaybeXS::false()) x 3 ],
    t => [ (JSON::MaybeXS::true())  x 3 ],
  };

  $logger->log_event('tf-thing' => [ cond => $struct ]);

  messages_ok(
    $logger,
    [
      'event=tf-thing cond.b.0=1 cond.b.1=0 cond.f.0=0 cond.f.1=0 cond.f.2=0 cond.t.0=1 cond.t.1=1 cond.t.2=1',
    ],
    "JSON bools do what we expect",
  );
};

done_testing;
