use strict;
use warnings;

use Log::Dispatchouli;
use Test::More tests => 3;
use Test::Deep;

my $logger = Log::Dispatchouli->new({
  ident     => $0,
  to_self   => 1,
  to_stderr => 0,
  to_stdout => 0,
});

isa_ok($logger, 'Log::Dispatchouli');

$logger->log([ "point: %s", {x=>1,y=>2} ]);
$logger->log_debug('this will not get logged');

cmp_deeply(
  $logger->events,
  [ superhashof({ message => re(qr/\Qpoint: {{{"x": 1, "y": 2}}}\E\z/) }) ],
  "events with struts logged to self",
);

eval { $logger->log_fatal([ 'this is good: %s', [ 1, 2, 3 ] ]) };
like($@, qr(good: {{\[), "log_fatal is fatal");
