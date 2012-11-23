#!perl -T

use Test::More tests => 3;

BEGIN {
        use_ok( 'Tapper::Testplan::Reporter' );
        use_ok( 'Tapper::Testplan::Generator' );
        use_ok( 'Tapper::Testplan::Plugins::Taskjuggler' );
}
