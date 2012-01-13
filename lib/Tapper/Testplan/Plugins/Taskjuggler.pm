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
use Tapper::Model 'model';
use Tapper::Testplan::Utils;


# extends 'Tapper::Testplan::Plugins';

has cfg        => ( is => 'ro');

=head1 NAME

Tapper::Testplan::Reporter::Plugins::Taskjuggler - Main module for testplan reporting!


=head1 SYNOPSIS


    use Tapper::Testplan::Reporter;

    my $foo = Tapper::Testplan::Reporter->new();

=head1 FUNCTIONS

=head2 fetch_data

Get the data about platforms and data from cache or remote.

@return array - data about all platforms

=cut

sub fetch_data
{
        my ($self) = @_;
        my $cache = CHI->new( driver => 'File',
                              root_dir => $self->cfg->{cacheroot}
                            );
        my @platforms;
        my $platforms = $cache->get( 'reports' );
        return $platforms if $platforms;
        my $mech = WWW::Mechanize->new();
        $mech->ssl_opts( verify_hostname => 0 );
        $mech->get($self->cfg->{url});
        my @platform_files = $mech->find_all_links( text_regex => qr/Tapper_/i );
        foreach my $file (@platform_files) {
                my ($platform_name) = $file->url =~ m/Tapper_(.+)_Matrix/;
                $platform_name    =~ tr/_/-/;
                my $tasks = Text::CSV::Slurp->load(string     => $mech->get($file->url)->content(),
                                                  binary   => 1,
                                                  sep_char => ";"
                                                 );
                foreach my $task (@{$tasks || [] }) {
                        $task->{Start} = $task->{Start}                               ?
                          DateTime::Format::DateParse->parse_datetime($task->{Start}) :
                                    DateTime::Infinite::Past->new();
                        $task->{End}   = $task->{End}                                 ?
                          DateTime::Format::DateParse->parse_datetime($task->{End})   :
                                    DateTime::Infinite::Future->new();
                }

                my $platform = {name  => $platform_name,
                                tasks => $tasks};
                push @platforms, $platform;
        }
        $cache->set( 'platforms', \@platforms, $self->cfg->{cachetime} );

        return \@platforms;
}


=head2 get_testplan_color

Get a color code for the success of this test plan. The returned color
codes have the following meaning.
'green'  - successfully tested
'yellow' - not all tests run but not errors yet
'red'    - at least one test failed
'black'  - no test defined

@param hash ref - success overview

@return string - 'green', 'yellow', 'red', 'black'

=cut

sub get_testplan_color
{
        my ($self, $task) = @_;

        if ( not (ref $task eq 'HASH'       and
                  defined $task->{tests_all} and
                  defined $task->{tests_finished}) ) {
                return 'black';
        }
        # no tests for task defined
        elsif (not @{$task->{tests_all}}) {
                return 'black';
        }
        # at least on test was already executed and has failed
        elsif ($task->{success} < 100 and @{$task->{tests_finished}}) {
                return 'red';
        }
        # no failed test, but not all finished yet
        elsif (@{$task->{tests_all}} >
                 @{$task->{tests_finished}}) {
                return 'yellow';
        }
        # no failed test and all finished
        else {
                return 'green';
        }
}



=head2

Prepare a task overview for WebGUI.

@optparam hash ref - contains "start" and "end" DateTime object

@return array ref  - contains hash refs

=cut

sub prepare_task_data
{
        my ($self, $times) = @_;

        my $now       = DateTime->now();
        my @reports   = @{$self->fetch_data() || []};
        my $interval;
        my $util     = Tapper::Testplan::Utils->new();

        foreach my $platform (@reports) {
        TASK:
                foreach my $task (@{$platform->{tasks} || [] }) {
                        my $start_time = $task->{Start};       delete $task->{Start};
                        my $end_time   = $task->{End};         delete $task->{End};
                        my $task_name  = $task->{'Task Name'}; delete $task->{'Task Name'};


                        foreach my $subtask (keys %$task) {
                                if ($task->{$subtask}) {
                                        my $db_path = $task->{$subtask};
                                        # we need more information on subtask hashes than TJ provides
                                        $task->{$subtask} = { name => $db_path };

                                        $db_path =~ tr|.|/|;
                                        my $task_success         = $util->get_testplan_success($db_path, $interval);

                                        $task->{$subtask}{color} = $self->get_testplan_color($task_success);
                                        $task->{$subtask}{id}    = $task_success->{testplan} ? $task_success->{testplan}->id : 'undef';
                                }
                        }

                        $platform->{vendors} = [ keys %$task ] unless $platform->{vendors};
                        $task->{start}       = $start_time;
                        $task->{end}         = $end_time;
                        $task->{name}        = $task_name;

                }
        }
        return \@reports;
}


=head2 get_platforms

Get a list of platforms together with their associated tasks.

=cut

=head2 get_tasks

Get a list of testplans we want reports for.

@optparam hash ref - contains "start" and "end" DateTime object

@return array - contains DBIC result objects

=cut

sub get_tasks
{

        my ($self, $times) = @_;

        my $now       = DateTime->now();
        my @reports;
        my $last_week  = DateTime->now();
        $last_week->subtract(weeks => 1);

        foreach my $platform (@{$self->fetch_data() || []}) {
        TASK:
                foreach my $task (@{$platform->{tasks} || [] }) {
                        my $start_time = $task->{Start};       delete $task->{Start};
                        my $end_time   = $task->{End};         delete $task->{End};
                        my $task_name  = $task->{'Task Name'}; delete $task->{'Task Name'};

                        if ($times and ref $times eq 'HASH') {
                                next TASK if ( $start_time > $times->{start} or
                                  $end_time < $times->{end});
                        } else {
                                next TASK if $start_time > $now;
                        }


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
                                                     Cc      => $self->cfg->{mailcc},
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
        my $parser    = DateTime::Format::Natural->new(time_zone => 'local');
        my $formatter = DateTime::Format::Strptime->new(pattern     => '%Y-%m-%d-00:00-%z', time_zone => 'local');
 REPORT:
        for (my $num=0; $num < int @reports; $num++) { # need to know when we reached the last report
                my $report = $reports[$num];
                $report->{work_end} = $report->{end}->set_formatter($formatter);
                $report->{path} =~ s|/|.|g;
                $report->{work} = sprintf ("%.2f",100/(int @reports));
                $report->{headline} = $report->{name};

                if (@{$report->{tests_all}} < 1) {
                        $report->{status}   = 'red';
                        $report->{summary}  = "No tests defined";
                        $report->{details} .= "Unable to find a test plan instance for this task. ";
                        $report->{details} .= "Either no test plan was defined or the testplan generator skipped it for some reason";
                        next REPORT;
                }
                if (@{$report->{tests_all}} > @{$report->{tests_finished}}) {
                        $report->{status}   = 'yellow';
                        $report->{summary} = sprintf ("%.1f", (@{$report->{tests_finished}}/@{$report->{tests_all}})*100);
                        $report->{summary}.= "% successful (";
                        $report->{summary}.= int @{$report->{tests_finished}};
                        $report->{summary}.= " of ";
                        $report->{summary}.= int @{$report->{tests_all}};
                        $report->{summary}.= "). ";
                        $report->{summary}.= sprintf ("%.1f", (1 - @{$report->{tests_finished}} / @{$report->{tests_all}})*100);
                        $report->{summary}.= "% unfinished (";
                        $report->{summary}.= @{$report->{tests_all}} - @{$report->{tests_finished}};
                        $report->{summary}.= " of ";
                        $report->{summary}.= int @{$report->{tests_all}};
                        $report->{summary}.= ").";

                } elsif ($report->{success} < 100) {
                        $report->{status}  = 'red';
                        $report->{summary} = 'Success ratio '.$report->{success}.'%';
                } else {
                        $report->{status}   = 'green';
                        $report->{summary} = "All tests successful for this test plan";
                }
                $report->{details} = "=== Link to testplan ===\n";
                if ($report->{testplan}) {
                        my $url = "$base_url/tapper/testplan/id/".$report->{testplan}->id;
                        $report->{details}.= "[$url $url]";
                } else {
                        $report->{details}.= "No testplan instance found";
                }


        }
        my $macros = { start_date => $parser->parse_datetime("this monday at 0:00")->set_formatter($formatter),
                       end_date   => $parser->parse_datetime("next monday at 0:00")->set_formatter($formatter),
                       reports    => [ @reports ] };
        my $tt = Template->new();
        my $ttapplied;
        $tt->process(\$mail_template, $macros, \$ttapplied) || die $tt->error();
        $self->send_mail($ttapplied);
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

