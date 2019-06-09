package PowerManagement::Any;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::ger;

use Exporter::Rinci qw(import);
use IPC::System::Options 'system', 'readpipe', -log=>1;

our %SPEC;

$SPEC{':package'} = {
    v => 1.1,
    summary => 'Common interface to some power management tasks',
};

our %argopt_quiet = (
    quiet => {
        summary => "Don't output anything on command-line, ".
            "just return appropriate exit code",
        schema => 'true*',
        cmdline_aliases => {q=>{}, silent=>{}},
    },
);

# XXX probably should refactor this into Systemd::Util later
sub _target_is_masked {
    my $target = shift;

    my ($out, $err);
    # systemctl status returns exit code=3 for dead/inactive status, so we
    # explicitly turns log=0 here.
    system({capture_stdout=>\$out, capture_stderr=>\$err, log=>0},
           "systemctl", "status", $target);
    if ($? && (my $exit_code = $? < 0 ? $? : $? >> 8) != 3) {
        log_warn "systemctl status failed, exit code=%d, stderr=%s",
            $exit_code, $err;
        return [500, "systemctl status failed with exit code=$exit_code"];
    }
    $out =~ /^\s*Loaded: ([^(]+)/m or do {
        return [412, "Cannot parse 'systemctl status $target': $out"];
    };
    my $loaded_status = $1;
    my $is_masked;
    if ($loaded_status =~ /not-found/) {
        return [412, "System does not have $target"];
    } elsif ($loaded_status =~ /masked/) {
        $is_masked = 1;
    } elsif ($loaded_status =~ /loaded/) {
        $is_masked = 0;
    } else {
        return [412, "Unrecognized loaded status of $target: ".
                    "$loaded_status"];
    }
    [200, "OK", $is_masked];
}

sub _prevent_or_unprevent_sleep_or_check {
    my ($which, %args) = @_;

  SYSTEMD:
    {
        log_trace "Checking if system is running systemd ...";

        my ($res, $is_masked);

        require Systemd::Util;
        $res = Systemd::Util::systemd_is_running();
        unless ($res->[0] == 200 && $res->[2]) {
            log_trace "systemd is not running or cannot determine, ".
                "skipped using systemd (%s)", $res;
            last;
        }

        $res = _target_is_masked("sleep.target");
        unless ($res->[0] == 200) {
            return $res;
        }
        $is_masked = $res->[2];
        return [200, "OK", $is_masked, {
            'cmdline.exit_code' => !$is_masked,
            'cmdline.result' => $args{quiet} ? '' :
                "Sleep is ".($is_masked ? "prevented" : "NOT prevented"),
        }] if $which eq 'check';
        return [304, "sleep.target already masked"]
            if $which eq 'prevent' && $is_masked;
        return [304, "sleep.target already unmasked"]
            if $which eq 'unprevent' && !$is_masked;

        my $action = $which eq 'prevent' ? 'mask' : 'unmask';
        my ($out, $err);
        system({capture_stdout=>\$out, capture_stderr=>\$err},
               "systemctl", $action, "sleep.target");
        #if ($?) {
        #    return [500, "Error when running 'systemctl $action sleep.target'".
        #                ": \$?=$?, stderr=$err"];
        #}

        # check again target is actually masked/unmasked
        $res = _target_is_masked("sleep.target");
        unless ($res->[0] == 200) {
            return $res;
        }
        $is_masked = $res->[2];
        return [500, "Failed to mask sleep.target"]
            if $which eq 'prevent' && !$is_masked;
        return [304, "Failed to unmask sleep.target"]
            if $which eq 'unprevent' && $is_masked;

        return [200, "OK", undef, {'func.mechanism' => 'systemd'}];
    } # SYSTEMD

    [412, "Don't know how to perform prevent/unprevent sleep on this system"];
}

$SPEC{'prevent_sleep'} = {
    v => 1.1,
    summary => 'Prevent system from sleeping',
    description => <<'_',

Will also prevent system from hybrid sleeping, suspending, or hibernating. The
effect is permanent (survives reboot); you need to `unprevent_sleep()` to
reverse the effect.

Note that this does not prevent screen blanking or locking (screensaver
activating); see <pm:Screensaver::Any> for routines that disable screensaver.

On systems that run Systemd, this is implemented by masking `sleep.target`. It
automatically also prevents `suspend.target`, `hybrid-sleep.target`, and
`hibernate.target` from activating. (Note that masking `systemd-suspend.service`
should also achieve the same result.)

Not implemented yet for other systems. Patches welcome.

_
    args => {},
};
sub prevent_sleep {
    _prevent_or_unprevent_sleep_or_check('prevent', @_);
}

$SPEC{'unprevent_sleep'} = {
    v => 1.1,
    summary => 'Reverse the effect of prevent_sleep()',
    description => <<'_',

See `prevent_sleep()` for more details.

_
    args => {},
};
sub unprevent_sleep {
    _prevent_or_unprevent_sleep_or_check('unprevent', @_);
}

$SPEC{'sleep_is_prevented'} = {
    v => 1.1,
    summary => 'Check if sleep has been prevented',
    description => <<'_',

The CLI return exit code 0 if sleep has been prevented.

See `prevent_sleep()` for more details.

_
    args => {
        %argopt_quiet,
    },
    examples => [
        {
            summary => 'Run a heavy task if sleep has been prevented on this laptop',
            src => '[[prog]] -q && some-heavy-task',
            src_plang => 'bash',
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],
};
sub sleep_is_prevented {
    _prevent_or_unprevent_sleep_or_check('check', @_);
}

1;
# ABSTRACT:

=head1 NOTES
