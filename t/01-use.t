#!perl -T

use Test::More;

@modules =  (
             'Tapper::Testplan::Reporter',
             'Tapper::Testplan::Plugins::Taskjuggler',
            );

plan tests => 2 * int @modules;
foreach my $module (@modules) {

        use_ok($module);
        my $obj = $module->new();
        isa_ok($obj, $module);
}


