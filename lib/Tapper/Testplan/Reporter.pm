package Tapper::Testplan::Reporter;

use warnings;
use strict;
use 5.010;

use Moose;
use Tapper::Config;
use Tapper::Model 'model';

extends 'Tapper::Testplan';

=head1 NAME

Tapper::Testplan::Reporter - Main module for testplan reporting!


=head1 SYNOPSIS


    use Tapper::Testplan::Reporter;

    my $foo = Tapper::Testplan::Reporter->new();

=head1 FUNCTIONS

=head2 run

=cut

sub run
{
        my ($self)    = @_;
        my $plugin    = Tapper::Config->subconfig->{testplans}{reporter}{plugin}{name} || 'Taskjuggler';
        my $now       = time();
        my $intervall = Tapper::Config->subconfig->{testplans}{reporter}{interval};

        eval "use Tapper::Testplan::Plugins::$plugin";
        my $reporter = "Tapper::Testplan::Plugins::$plugin"->new(cfg => Tapper::Config->subconfig->{testplans}{reporter}{plugin});

          my @reports;
 TASK:
        foreach my $task ($reporter->get_tasks()) {

                my $path  = $task->{path};


                my $instances = model('TestrunDB')->resultset('TestplanInstance')->search
                  ({ path => $path,
                     created_at => { '>=' => $now - $intervall }});
                my @testruns = map {$_->testruns} $instances->all;
                my @testrun_ids = map {$_->id } @testruns;

                if (@testrun_ids) {
                        my $stats   = model('ReportsDB')->resultset('ReportgroupTestrunStats')->search({testrun_id => {-in => [@testrun_ids]}});
                        my $success = 0;
                        if ($stats->count) {
                                map { $success += $_->success_ratio } $stats->all;
                                $task->{success} = $success / $stats->count;
                        } else {
                                $task->{success} = 0;
                        }
                        $task->{tests_all}       = [ @testruns ];
                        $task->{tests_scheduled} = [ grep {$_->testrun_scheduling->status eq 'schedule'} @testruns ];
                        $task->{tests_running}   = [ grep {$_->testrun_scheduling->status eq 'running'}  @testruns ];
                        $task->{tests_finished}  = [ grep {$_->testrun_scheduling->status eq 'finished'} @testruns ];
                } else {
                        $task->{success} = 0;
                        $task->{tests_all}       = [];
                        $task->{tests_scheduled} = [];
                        $task->{tests_running}   = [];
                        $task->{tests_finished}  = [];
                }
                push @reports, $task;
        }
        $reporter->send_reports(@reports);
}

=head1 AUTHOR

OSRC SysInt Team, C<< <osrc-sysint at elbe.amd.com> >>

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

1; # End of Tapper::Testplan::Reporter
