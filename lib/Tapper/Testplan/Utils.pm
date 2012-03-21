package Tapper::Testplan::Utils;

use warnings;
use strict;
use 5.010;

use Moose;
use Tapper::Model 'model';


=head1 NAME

Tapper::Testplan::Utils - Utility functions for testplan modules and plugins

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
        my $instance = $instances->first;


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


=head1 AUTHOR

AMD OSRC Tapper Team, C<< <tapper at amd64.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-tapper-testplan-reporter at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Tapper-Testplan-Reporter>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Tapper::Testplan::Reporter


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Tapper-Testplan-Reporter>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Tapper-Testplan-Reporter>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Tapper-Testplan-Reporter>

=item * Search CPAN

L<http://search.cpan.org/dist/Tapper-Testplan-Reporter/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 COPYRIGHT & LICENSE

Copyright 2008-2011 AMD OSRC Tapper Team, all rights reserved.

This program is released under the following license: freebsd

=cut

1; # End of Tapper::Testplan::Utils;

