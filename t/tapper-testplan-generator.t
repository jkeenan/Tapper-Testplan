
use strict;
use warnings;
use 5.010;

use Test::More;
use Hash::Merge 'merge';

use Tapper::Schema::TestTools;
use Tapper::Model 'model';

use DateTime::Format::Natural;
use DateTime::Format::Strptime;
use Test::Fixture::DBIC::Schema;
use Test::MockModule;
use POSIX ":sys_wait_h";
use HTTP::Daemon;
use HTTP::Status;

use Data::Dumper;

$SIG{CHLD} = 'IGNORE';
my $d = HTTP::Daemon->new || die "No HTTP daemon:$!";

my $pid = fork();
die "No fork: $!" unless defined $pid;
if ($pid == 0) {
        while (my $c = $d->accept) {
                while (my $r = $c->get_request) {
                        if ($r->method eq 'GET') {
                                if ($r->uri->path eq "/") {
                                        $c->send_file_response("t/htdocs/index.html");
                                } else {
                                        $c->send_file_response("t/htdocs/".$r->uri->path);
                                }
                        }
                }
                $c->close;
                undef($c);
        }
        exit 1;
}


# -----------------------------------------------------------------------------------------------------------------
construct_fixture( schema  => testrundb_schema, fixture => 't/fixtures/testrundb/testrun_with_testplan.yml' );
construct_fixture( schema  => reportsdb_schema, fixture => 't/fixtures/reportsdb/report.yml' );
# -----------------------------------------------------------------------------------------------------------------


BEGIN{
        use_ok('Tapper::Testplan::Generator');
}
Hash::Merge::set_behavior( 'RIGHT_PRECEDENT' );

Tapper::Config->subconfig->{testplans} = merge(
                                                Tapper::Config->subconfig->{testplans},
                                                { reporter   =>
                                                  { plugin   => { name     => 'Taskjuggler',
                                                                  url      => $d->url,
                                                                },
                                                    interval => 1*24*60*60,
                                                  }
                                                });



qx(touch t/htdocs/Tapper_barracuda_g34_Matrix.csv);
my $reporter = Tapper::Testplan::Generator->new();
isa_ok($reporter, 'Tapper::Testplan::Generator');
my @instances;
eval {
        @instances = $reporter->run();
};
fail($@) if $@;
is(int @instances, 1, 'One instance created');

if (@instances) {
        my $inst = model('TestrunDB')->resultset('TestplanInstance')->find($instances[0]);
        ok($inst, 'Testplan instance in db');
        is($inst->name, 'KVM: Support Flush by ASID', 'Name of the testplan instance');
        my @preconditions =  map {$_->precondition_as_hash} $inst->testruns->first->ordered_preconditions;
        is_deeply(\@preconditions, [
          {
            'arch' => 'linux64',
            'mount' => '/',
            'precondition_type' => 'image',
            'partition' => 'sda2',
            'image' => 'suse/suse_sles10_64b_smp_raw.tar.gz'
          },
          {
            'protocol' => 'local',
            'dest' => '/bin/',
            'name' => '/data/bancroft/artemis/live/repository/testprograms/uname_tap/uname_tap.sh',
            'precondition_type' => 'copyfile'
          },
          {
            'protocol' => 'local',
            'dest' => '/bin/',
            'name' => '/data/bancroft/artemis/live/repository/packages/artemisutils/kernel/gen_initrd.sh',
            'precondition_type' => 'copyfile'
          },
          {
            'filename' => 'kernel/x86_64/linux-2.6.31_rc6.2009-08-14.x86_64.tgz',
            'precondition_type' => 'package'
          },
          {
            'options' => [
                           '2.6.31-rc6'
                         ],
            'filename' => '/bin/gen_initrd.sh',
            'precondition_type' => 'exec'
          },
          {
            'timeout' => '1000',
            'precondition_type' => 'testprogram',
            'program' => '/opt/artemis/bin/artemis-netperf-server'
          }
        ], 'Preconditions on first created testrun');

} else {
        fail "Can not test without instances";
}

kill 15, $pid;


done_testing();
