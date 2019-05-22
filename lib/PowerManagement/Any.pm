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

sub _prevent_or_unprevent_sleep {
    my ($which, %args) = @_;

  SYSTEMD:
    {
        log_trace "Checking if system is running systemd ...";
        require Systemd::Util;
        my $res = Systemd::Util::systemd_is_running();
        unless ($res->[0] == 200 && $res->[2]) {
            log_trace "systemd is not running or cannot determine, ".
                "skipped using systemd";
            last;
        }

        # XXX probably should refactor this into Systemd::Util later
        my ($out, $err);
        system({capture_stdout=>\$out, capture_stderr=>\$err},
               "systemctl", "status", "sleep.target");
        if ($?) {
            return [500, "Error when running 'systemctl status sleep.target'".
                        ": \$?=$?, stderr=$err"];
        }
        $out =~ /^\s*Loaded: ([^(]+)/m or do {
            return [412, "Cannot parse 'systemctl status sleep.target'"];
        };
        my $loaded_status = $1;
        my $is_masked;
        if ($loaded_status =~ /not-found/) {
            return [412, "System does not have 'sleep.target'"];
        } elsif ($loaded_status =~ /masked/) {
            $is_masked = 1;
        } elsif ($loaded_status =~ /loaded/) {
            $is_masked = 0;
        } else {
            return [412, "Unrecognized loaded status of 'sleep.target': ".
                        "$loaded_status"];
        }

        return [304, "sleep.target already masked"]
            if $which eq 'prevent' && $is_masked;
        return [304, "sleep.target already unmasked"]
            if $which eq 'unprevent' && !$is_masked;

        my $action = $which eq 'prevent' ? 'mask' : 'unmask';
        system({capture_stdout=>\$out, capture_stderr=>\$err},
               "systemctl", $action, "sleep.target");
        if ($?) {
            return [500, "Error when running 'systemctl $action sleep.target'".
                        ": \$?=$?, stderr=$err"];
        }

        # XXX check if target is actually masked/unmasked

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
    _prevent_or_unprevent_sleep('prevent', @_);
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
    _prevent_or_unprevent_sleep('unprevent', @_);
}

1;
# ABSTRACT:

=head1 NOTES
