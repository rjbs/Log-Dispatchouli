use inc::Module::Install;

all_from('lib/Log/Dispatchouli.pm');

requires('Carp');
requires('Log::Dispatch');
requires('Params::Util');
requires('Scalar::Util');
requires('String::Flogger');

auto_manifest;

WriteAll();
