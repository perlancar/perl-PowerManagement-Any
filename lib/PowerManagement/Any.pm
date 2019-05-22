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

# XXX probably should refactor this into Systemd::Util later
sub _target_is_masked {
    my $target = shift;

    my ($out, $err);
    system({capture_stdout=>\$out, capture_stderr=>\$err},
           "systemctl", "status", $target);
    # systemctl status always returns exit code=3, even for unknown target?
    #if ($?) {
    #    return [500, "Error when running 'systemctl status sleep.target'".
    #                ": \$?=$?, stderr=$err"];
    #}
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
        return [200, "OK", $is_masked] if $which eq 'check';
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

        return [200, "OK", {'func.mechanism' => 'systemd'}];
    } # SYSTEMD

    [412, "Don't know how to perform prevent/unprevent sleep on this system"];
}

$SPEC{'prevent_sleep'} = {
    v => 1.1,
    summary => 'Prevent system from sleeping',
    description => <<'_',

Will also prevent system from hybrid sleeping, suspending, or hibernating. The
effect is permanent; you need to `unprevent_sleep()` to reverse the effect.

Note that this does not prevent screen blanking or locking (screensaver
activating); see <pm:Screensaver::Any> for routines that disable screensaver.

On systems that run Systemd, this is implemented by masking the sleep.target. It
automatically also prevents suspend.target, hybrid-sleep.target, and
hibernate.target from activating.

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

See `prevent_sleep()` for more details.

_
    args => {},
};
sub sleep_is_prevented {
    _prevent_or_unprevent_sleep_or_check('check', @_);
}

1;
# ABSTRACT:

=head1 NOTES
