use inc::Module::Install;

name     'Tapper-Testplan';
all_from 'lib/Tapper/Testplan.pm';
author   'OSRC SysInt Team <osrc-sysint@elbe.amd.com>';
license  'perl';

build_requires 'Test::More';

requires 'Moose' => 0;

requires 'Tapper::Config'  => 2.010076;
requires 'Tapper::Model' => 2.010020;
requires 'CHI' => 0;
requires 'DateTime' => 0;
requires 'DateTime::Format::DateParse' => 0;
requires 'Text::CSV::Slurp' => 0;
requires 'DateTime' => 0;
requires 'DateTime::Format::DateParse' => 0;
requires 'DateTime::Format::Natural' => 0.91; # older versions don't parse "next monday at 0:00"
requires 'DateTime::Format::Strptime' => 0;
requires 'Email::Sender::Simple' => 0;
requires 'Email::Sender::Transport::SMTP' => 0;
requires 'Email::Simple' => 0;
requires 'File::ShareDir' => 0;
requires 'File::Slurp' => 0;
requires 'Moose' => 0;
requires 'Template' => 0;
requires 'Text::CSV::Slurp' => 0;
requires 'WWW::Mechanize' => 0;


auto_install;

WriteAll;

