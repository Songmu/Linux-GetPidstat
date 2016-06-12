package Linux::GetPidstat::Collector;
use 5.008001;
use strict;
use warnings;

use Capture::Tiny qw/capture/;
use Parallel::ForkManager;
use Linux::GetPidstat::Collector::Parser;

my $GETPIDSTAT_DEBUG = sub {
    $ENV{GETPIDSTAT_DEBUG} ? 1 : 0;
};

sub new {
    my ( $class, %opt ) = @_;
    bless \%opt, $class;
}

sub get_pidstats_results {
    my ($self, $program_pid_mapping) = @_;

    my $ret_pidstats;

    my $pm = Parallel::ForkManager->new(scalar @$program_pid_mapping);
    $pm->run_on_finish(sub {
        if (my $ret = $_[5]) {
            my ($program_name, $ret_pidstat, $stdout, $stderr) = @$ret;

            print $stdout, "\n" if $stdout;
            warn  $stderr       if $stderr;

            if ($program_name && $ret_pidstat) {
                push @{$ret_pidstats->{$program_name}}, $ret_pidstat;
                return;
            }
        }

        warn "Failed to collect metrics\n" if $GETPIDSTAT_DEBUG->();
    });

    METHODS:
    for my $info (@$program_pid_mapping) {
        my $program_name = $info->{program_name};
        my $pid          = $info->{pid};

        if (my $child_pid = $pm->start) {
            printf "child_pid=%d, program_name=%s, target_pid=%d\n",
                $child_pid, $program_name, $pid if $GETPIDSTAT_DEBUG->();
            next METHODS;
        }

        my $ret_pidstat;
        my ($stdout, $stderr) = capture {
            $ret_pidstat = $self->get_pidstat($pid);
            unless ($ret_pidstat && %$ret_pidstat) {
                warn sprintf
                    "Failed getting pidstat: pid=%d, target_pid=%d, program_name=%s\n",
                    $$, $pid, $program_name;
            }
        };

        $pm->finish(0, [$program_name, $ret_pidstat, $stdout, $stderr]);
    }
    $pm->wait_all_children;

    return summarize($ret_pidstats);
}

sub get_pidstat {
    my ($self, $pid) = @_;
    my $command = _command_get_pidstat($pid, $self->{interval});
    my ($stdout, $stderr, $exit) = capture { system $command };

    if (!$stdout or $stderr or $exit != 0) {
        chomp($stderr);
        warn sprintf
            "Failed a command: %s, pid=%d, stdout=%s, stderr=%s, exit=%s\n",
            $command, $$, $stdout, $stderr, $exit;
        return;
    }

    my @lines = split '\n', $stdout;
    return parse_pidstat_output(\@lines);
}

# for mock in tests
sub _command_get_pidstat {
    my ($pid, $interval) = @_;
    return "pidstat -h -u -r -s -d -w -p $pid 1 $interval";
}

sub summarize($) {
    my $ret_pidstats = shift;

    my $summary = {};

    # in : backup_mysql => [ { cpu => 21.0... } ... ] ...
    # out: backup_mysql => { cpu => 42.0 } ... } ...
    while (my ($program_name, $rets) = each %$ret_pidstats) {
        for my $ret (@{$rets}) {
            while (my ($metric_name, $metric) = each %$ret) {
                $summary->{$program_name}->{$metric_name} += $metric;
            }
        }
    }
    return $summary;
}

1;
__END__

=encoding utf-8

=head1 NAME

Linux::GetPidstat::Collector - Collect pidstats' results

=head1 SYNOPSIS

    use Linux::GetPidstat::Collector;

    my $ret_pidstats = Linux::GetPidstat::Collector->new(
        interval => '60',
    )->get_pidstats_results($program_pid_mapping);

=cut
