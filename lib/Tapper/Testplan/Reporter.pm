package Tapper::Testplan::Reporter;

use warnings;
use strict;
use 5.010;

use Moose;
use Tapper::Config;
use Tapper::Model 'model';
use Hash::Merge 'merge';
use Tapper::Testplan::Utils;

extends 'Tapper::Testplan';

=head1 NAME

Tapper::Testplan::Reporter - Main module for testplan reporting!


=head1 SYNOPSIS


    use Tapper::Testplan::Reporter;

    my $foo = Tapper::Testplan::Reporter->new();

=head1 FUNCTIONS


=head2 run

Get the tasks to report and do the reporting.

@optparam array - list of tasks names

=cut

sub run
{
        my ($self, @tasks)    = @_;
        my $plugin    = Tapper::Config->subconfig->{testplans}{reporter}{plugin}{name} || 'Taskjuggler';
        my $intervall;

        eval "use Tapper::Testplan::Plugins::$plugin";
        my $reporter = "Tapper::Testplan::Plugins::$plugin"->new(cfg => Tapper::Config->subconfig->{testplans}{reporter}{plugin});
        my $util     = Tapper::Testplan::Utils->new();

        my @reports;

        if (not @tasks) {
                @tasks     = $reporter->get_tasks();
                $intervall = Tapper::Config->subconfig->{testplans}{reporter}{interval};
        }

 TASK:
        foreach my $task (@tasks) {

                my $task_success = $util->get_testplan_success($task->{path}, $intervall);
                 Hash::Merge::set_behavior( 'LEFT_PRECEDENT' );
                $task = merge($task, $task_success);
                push @reports, $task;
        }
        $reporter->send_reports(@reports);
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

1; # End of Tapper::Testplan::Reporter
