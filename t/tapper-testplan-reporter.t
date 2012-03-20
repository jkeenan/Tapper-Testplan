
use strict;
use warnings;
use 5.010;

use Test::More;
use Test::Differences;
use Hash::Merge 'merge';

use Tapper::Schema::TestTools;

use DateTime::Format::Natural;
use DateTime::Format::Strptime;
use Test::Fixture::DBIC::Schema;
use Test::MockModule;
use POSIX ":sys_wait_h";
use HTTP::Daemon;
use HTTP::Status;

use Data::Dumper;
if ($ENV{HARNESS_IS_VERBOSE}) {
        diag '################################################################################ #';
        diag '                                                                                 #';
        diag 'osrc.kernel.barracuda.server.kvm.svm_asid.tapper.LK_39        - no tests defined #';
        diag 'osrc.kernel.barracuda.server.kvm.svm_asid.tapper.SLES_11SP2   - success < 100%   #';
        diag 'osrc.kernel.barracuda.server.kvm.svm_decode.tapper.LK_38      - unfinished tests #';
        diag 'osrc.kernel.barracuda.server.kvm.svm_decode.tapper.SLES_11SP2 - all green        #';
        diag 'osrc.kernel.barracuda.server.kvm.red_task.tapper.SLES_11SP2   - red but finished #';
        diag 'osrc.kernel.barracuda.server.kvm.red_task.tapper.LK_38        - red but finished #';
        diag '                                                                                 #';
        diag '################################################################################ #';
}


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
qx(touch t/htdocs/Tapper_barracuda_g34_Matrix.csv);

my $mailtext;
my $mock_tj = Test::MockModule->new('Tapper::Testplan::Plugins::Taskjuggler');
$mock_tj->mock('send_mail', sub {(undef, $mailtext) = @_; return});



# -----------------------------------------------------------------------------------------------------------------
construct_fixture( schema  => testrundb_schema, fixture => 't/fixtures/testrundb/testrun_with_testplan.yml' );
construct_fixture( schema  => reportsdb_schema, fixture => 't/fixtures/reportsdb/report.yml' );
# -----------------------------------------------------------------------------------------------------------------


BEGIN{
        use_ok('Tapper::Testplan::Reporter');
}
Hash::Merge::set_behavior( 'RIGHT_PRECEDENT' );

Tapper::Config->subconfig->{testplans} = merge(
                                                Tapper::Config->subconfig->{testplans},
                                                { reporter   =>
                                                  { plugin   => { name      => 'Taskjuggler',
                                                                  url       => $d->url,
                                                                  cacheroot =>  '/tmp/cacheroot_test/'
                                                                },
                                                    interval => 1*24*60*60,
                                                  }
                                                });



my $reporter = Tapper::Testplan::Reporter->new();
isa_ok($reporter, 'Tapper::Testplan::Reporter');
eval {
        $reporter->run();
};
fail($@) if $@;

my $parser    = DateTime::Format::Natural->new(time_zone => 'local');
my $formatter = DateTime::Format::Strptime->new(pattern     => '%Y-%m-%d-00:00-%z', time_zone => 'local');
my $start     = $parser->parse_datetime("this monday");
my $end       = $parser->parse_datetime("next monday");
$start->set_formatter($formatter);
$end->set_formatter($formatter);
my $end_time  = DateTime::Format::DateParse->parse_datetime('3011-06-30-00:00')->set_formatter($formatter);
my $end_green = $parser->parse_datetime('next monday at 0:00')->set_formatter($formatter);
$end_green->subtract(hours => 1);
my $end_red = $parser->parse_datetime('next monday at 0:00')->set_formatter($formatter);
$end_red->add(weeks => 1)->subtract(hours => 1);


my $expected = "timesheet tapper $start - $end {
".
qq(  task osrc.kernel.barracuda.server.kvm.svm_asid.tapper.SLES_11SP2 {
    work 0%
    end $end_time
    status yellow "KVM: Support Flush by ASID" {
    summary
-8<-
No tests defined
->8-
    details
-8<-
Unable to find a test plan instance for this task.
->8-
    }
  }
  task osrc.kernel.barracuda.server.kvm.svm_asid.tapper.LK_39 {
    work 0%
    end $end_time
    status red "KVM: Support Flush by ASID" {
    summary
-8<-
Success ratio 75%
->8-
    details
-8<-
=== Link to testplan ===
[https://tapper/tapper/testplan/id/1 https://tapper/tapper/testplan/id/1]
->8-
    }
  }
  task only.to.get.work.fractions.task1 {
    work 0%
    end $end_time
    status yellow "KVM: Support Decode Assists" {
    summary
-8<-
No tests defined
->8-
    details
-8<-
Unable to find a test plan instance for this task.
->8-
    }
  }
  task osrc.kernel.barracuda.server.kvm.svm_decode.tapper.SLES_11SP2 {
    work 0%
    end $end_green
    status green "KVM: Support Decode Assists" {
    summary
-8<-
All tests successful for this test plan
->8-
    details
-8<-
=== Link to testplan ===
[https://tapper/tapper/testplan/id/3 https://tapper/tapper/testplan/id/3]
->8-
    }
  }
  task osrc.kernel.barracuda.server.kvm.svm_decode.tapper.LK_38 {
    work 0%
    end $end_time
    status yellow "KVM: Support Decode Assists" {
    summary
-8<-
33.3% successful (1 of 3). 66.7% unfinished (2 of 3).
->8-
    details
-8<-
=== Link to testplan ===
[https://tapper/tapper/testplan/id/2 https://tapper/tapper/testplan/id/2]
->8-
    }
  }
  task only.to.get.work.fractions.task1 {
    work 0%
    end $end_time
    status yellow "KVM: Support Decode Assists" {
    summary
-8<-
No tests defined
->8-
    details
-8<-
Unable to find a test plan instance for this task.
->8-
    }
  }
  task osrc.kernel.barracuda.server.kvm.red_task.tapper.SLES_11SP2 {
    work 0%
    end $end_red
    status yellow "Red task already finished" {
    summary
-8<-
No tests defined
->8-
    details
-8<-
Unable to find a test plan instance for this task.
->8-
    }
  }
  task osrc.kernel.barracuda.server.kvm.red_task.tapper.LK_38 {
    work 0%
    end $end_red
    status yellow "Red task already finished" {
    summary
-8<-
No tests defined
->8-
    details
-8<-
Unable to find a test plan instance for this task.
->8-
    }
  }
}
);

eq_or_diff($mailtext, $expected, 'Expected mail text');

kill 15, $pid;


done_testing();
