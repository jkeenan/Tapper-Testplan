package Tapper::Testplan::Utils;
# ABSTRACT: Utility functions for testplan modules and plugins

use warnings;
use strict;
use 5.010;

use Moose;
use Tapper::Model 'model';

=head1 SYNOPSIS

Some functions are needed for both standard testplan modules (like
Reporter or Generator) and plugin modules (like Taskjuggler).

    use Tapper::Testplan::Utils;

    my $foo = Tapper::Testplan::Utils->new();

=head1 FUNCTIONS

=head2 get_testplan_success

Get success overview for a task given by path. An optional second
argument gives a time in seconds.  Only results that are at most that
old are used.

@param string - path
@optparam int    - interval in seconds

@retval hash ref - contains
* test_all        - number of all tests
* tests_scheduled - number of tests scheduled but not yet started
* tests_finished  - number of currently running tests
* tests_finished  - number of already finished tests
* success         - current success ratio of the whole testplan in percent (may change later when not all tests are finished yet)

=cut

sub get_testplan_success
{
        my ($self, $path, $interval) = @_;
        my $now       = time();
        my $instances = model('TestrunDB')->resultset('TestplanInstance')->search
          ({ path => $path }, { order_by => {-desc => 'created_at' }}); # descending order, so first will be most recent
        $instances = $instances->search({created_at => { '>=' => $now - $interval }}) if $interval;

        # always use the most current,
        my $instance = $instances->search({}, {rows => 1})->first;


        my $task;
        if ($instance) {
                $task->{name} = $instance->name;
                my @testrun_ids = map {$_->id } $instance->testruns;
                my $stats   = model('ReportsDB')->resultset('ReportgroupTestrunStats')->search({testrun_id => {-in => [@testrun_ids]}});
                my $success = 0;
                if ($stats->count) {
                        map { $success += $_->success_ratio } $stats->all;
                        $task->{success} = $success / $stats->count;
                } else {
                        $task->{success} = 0;
                }
                $task->{testplan}        = $instance;
                $task->{tests_all}       = [ $instance->testruns->all ];
                $task->{tests_scheduled} = [ grep {$_->testrun_scheduling->status eq 'schedule'} $instance->testruns->all ];
                $task->{tests_running}   = [ grep {$_->testrun_scheduling->status eq 'running'}  $instance->testruns->all ];
                $task->{tests_finished}  = [ grep {$_->testrun_scheduling->status eq 'finished'} $instance->testruns->all ];
        } else {
                $task->{success} = 0;
                $task->{tests_all}       = [];
                $task->{tests_scheduled} = [];
                $task->{tests_running}   = [];
                $task->{tests_finished}  = [];
        }
        return $task;
}

1; # End of Tapper::Testplan::Utils;

