use strict;
use warnings;
use Test::More 0.98;
use Test::Fatal;
use Capture::Tiny qw/capture/;

use Linux::GetPidstat;

my %cli_default_opt = (
    pid_dir       => './pid',
    include_child => '1',
    interval      => '60',
    dry_run       => '1'
);

my $instance = Linux::GetPidstat->new;

like exception {
    $instance->run;
}, qr/pid_dir required/, "no pid_dir is not allowed";

subtest 'output to a file' => sub {
    my ($stdout, $stderr) = capture {
        $instance->run(%cli_default_opt);
    };
    my @stdout_lines = split /\n/, $stdout;
    is scalar @stdout_lines, 25 or diag $stdout;
    is $stderr, '' or diag $stderr;
};

$cli_default_opt{mackerel_api_key}      = 'dummy_key';
$cli_default_opt{mackerel_service_name} = 'dummy_name';

subtest 'output to a file and mackerel' => sub {
    my ($stdout, $stderr) = capture {
        $instance->run(%cli_default_opt);
    };
    my @stdout_lines = split /\n/, $stdout;
    is scalar @stdout_lines, 43, or diag $stdout;
    is $stderr, '' or diag $stderr;
};

done_testing;
