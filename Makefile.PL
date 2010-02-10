use inc::Module::Install;

all_from('lib/Log/Dispatchouli.pm');

requires('Carp');
requires('Log::Dispatch');
requires('Log::Dispatch::Array');
requires('Log::Dispatch::File');
requires('Log::Dispatch::Screen');
requires('Log::Dispatch::Syslog');
requires('Params::Util');
requires('Scalar::Util');
requires('String::Flogger');
requires('Sys::Syslog' => 0.16); # native socket type
requires('Try::Tiny');

auto_manifest;

WriteAll();
