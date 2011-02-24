package Tapper::Testplan::Plugins::Taskjuggler;

use warnings;
use strict;
use 5.010;

use CHI;
use DateTime::Format::DateParse;
use DateTime::Format::Natural;
use DateTime::Format::Strptime;
use DateTime;
use Email::Sender::Simple qw(sendmail);
use Email::Sender::Transport::SMTP;
use Email::Simple;
use File::ShareDir 'module_file';
use File::Slurp 'slurp';
use Moose;
use Template;
use Text::CSV::Slurp;
use WWW::Mechanize;


# extends 'Tapper::Testplan::Plugins';

has cfg => (is => 'ro');


=head1 NAME

Tapper::Testplan::Reporter::Plugins::Taskjuggler - Main module for testplan reporting!


=head1 SYNOPSIS


    use Tapper::Testplan::Reporter;

    my $foo = Tapper::Testplan::Reporter->new();

=head1 FUNCTIONS

=head2 get_tasks

Get a list of testplans we want reports for.

@return array - contains DBIC result objects

=cut

sub get_tasks
{

        my ($self) = @_;

        my $cache = CHI->new( driver => 'File',
                              root_dir => $self->cfg->{cacheroot}
                            );
        my $reports = $cache->get( 'reports' );

        my @reports;

        if (not $reports) {
                my $mech = WWW::Mechanize->new();
                $mech->get($self->cfg->{url});
                my @platforms = $mech->find_all_links( text_regex => qr/Tapper_/i );
                my @projects;
                my $now       = DateTime->now();

                foreach my $link (@platforms) {
                        push @projects, $mech->get($link->url)->content();
                }


                foreach my $project (@projects) {
                        my $data = Text::CSV::Slurp->load(string     => $project,
                                                          binary   => 1,
                                                          sep_char => ";"
                                                         );
                TASK:
                        foreach my $task (@{$data || [] }) {
                                my $start_time = $task->{Start}                               ?
                                  DateTime::Format::DateParse->parse_datetime($task->{Start}) :
                                            DateTime::Infinite::Past->new();
                                my $end_time   = $task->{End}                                 ?
                                  DateTime::Format::DateParse->parse_datetime($task->{End})   :
                                            DateTime::Infinite::Future->new();
                                my $task_name  = $task->{'Task Name'};
                                next TASK unless $start_time < $now and $end_time > ($now->subtract(weeks => 1));

                                delete $task->{Start};
                                delete $task->{End};
                                delete $task->{'Task Name'};

                        SUBTASK:
                                foreach my $subtask (keys %{$task || {}}) {

                                        next SUBTASK if not $task->{$subtask};
                                        $task->{$subtask} =~ s|\.|/|g;

                                        push @reports, {start => $start_time,
                                                        end   => $end_time,
                                                        name  => $task_name,
                                                        path  => $task->{$subtask}};
                                }
                        }
                }
                $cache->set( 'reports', \@reports, $self->cfg->{cachetime} );
        } else {
                @reports = @{$reports};
        }

        return @reports;
}

=head2 send_mail

Send the text as mail.

@param string - report text

@return undef

=cut

sub send_mail
{
        my ($self, $mailtext) = @_;
        my $transport = Email::Sender::Transport::SMTP->new({
                                                             host => $self->cfg->{mailhost},
                                                            });
        my $email = Email::Simple->create(
                                          header => [
                                                     To      => $self->cfg->{mailto},
                                                     From    => $self->cfg->{mailfrom},
                                                     Subject => "Test plans for ".DateTime->now,
                                                    ],
                                          body => $mailtext,
                                         );

        sendmail($email, { transport => $transport });
        return;
}

=head2 send_reports

Send a report based on the data received as parameter.

@param list of hash refs - contains reports

@return success - 0
@return error   - error string

=cut

sub send_reports
{
        my ($self, @reports) = @_;
        my $worksum = 0;
        my $base_url = $self->cfg->{base_url};

        my $mail_template = slurp module_file('Tapper::Testplan::Plugins::Taskjuggler', 'mail.template');
        my $parser    = DateTime::Format::Natural->new(time_zone   => 'Europe/Berlin');
        my $formatter = DateTime::Format::Strptime->new(pattern     => '%Y-%m-%d-00:00-%z');

 REPORT:
        for (my $num=0; $num < int @reports; $num++) { # need to know when we reached the last report
                my $report = $reports[$num];
                $report->{work_end} = $report->{end}->set_formatter($formatter);
                $report->{path} =~ s|/|.|g;
                $report->{work} = sprintf ("%.2f",100/(int @reports));

                if ($num == $#reports) {
                        $report->{work} =  sprintf ("%.2f", 100 - $worksum);
                } else {
                        $worksum += $report->{work};
                }
                if (@{$report->{tests_all}} < 1) {
                        $report->{status}   = 'red';
                        $report->{headline} = 'No tests defined';
                        next REPORT;
                }
                if ($report->{success} < 100) {
                        $report->{status}   = 'red';
                        $report->{headline} = 'Success ratio '.$report->{success}.'%';
                        $report->{details} = "== All testruns ==\n";
                        $report->{details}.= "$base_url/tapper/testruns/idlist/";
                        $report->{details}.= join ",",map {$_->id} @{$report->{tests_finished}};
                } elsif (@{$report->{tests_all}} > @{$report->{tests_finished}}) {
                        $report->{status}   = 'yellow';
                        $report->{headline} = sprintf ("%.1f", (@{$report->{tests_finished}}/@{$report->{tests_all}})*100);
                        $report->{headline}.= "% successful (";
                        $report->{headline}.= int @{$report->{tests_finished}};
                        $report->{headline}.= " of ";
                        $report->{headline}.= int @{$report->{tests_all}};
                        $report->{headline}.= "). ";
                        $report->{headline}.= sprintf ("%.1f", (1 - @{$report->{tests_finished}} / @{$report->{tests_all}})*100);
                        $report->{headline}.= "% unfinished (";
                        $report->{headline}.= @{$report->{tests_all}} - @{$report->{tests_finished}};
                        $report->{headline}.= " of ";
                        $report->{headline}.= int @{$report->{tests_all}};
                        $report->{headline}.= ").";

                        $report->{details} = "== Successful testruns ==\n";
                        $report->{details}.= "$base_url/tapper/testruns/idlist/";
                        $report->{details}.= join ",",map {$_->id} @{$report->{tests_finished}};
                        $report->{details}.= "\n\n== Unfinished testruns ==\n";
                        $report->{details}.= "$base_url/tapper/testruns/idlist/";
                        $report->{details}.= join ",",map {$_->id} (@{$report->{tests_running}}, @{$report->{tests_scheduled}});
                } else {
                        $report->{status}   = 'green';
                        $report->{headline} = "All tests successful for this test plan";
                        $report->{details} = "== Successful testruns ==\n";
                        $report->{details}.= "$base_url/tapper/testruns/idlist/";
                        $report->{details}.= join ",",map {$_->id} @{$report->{tests_finished}};
                }
        }
        my $macros = { start_date => $parser->parse_datetime("last monday")->set_formatter($formatter),
                       end_date => $parser->parse_datetime("next monday")->set_formatter($formatter),
                       reports => [ @reports ] };
        my $tt = Template->new();
        my $ttapplied;
        $tt->process(\$mail_template, $macros, \$ttapplied) || die $tt->error();
        $self->send_mail($ttapplied);
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

Copyright 2011 OSRC SysInt Team, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

1; # End of Tapper::Testplan::Reporter

