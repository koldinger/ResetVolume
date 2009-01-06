# GrabPlaylist.pm by Eric Koldinger (kolding@yahoo.com) October, 2004
#
# This code is derived from code with the following copyright message:
#
# SlimServer Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

package Plugins::ResetVolume::Plugin;

use strict;

use base qw(Slim::Plugin::Base);

use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Log;

use Plugins::ResetVolume::PlayerSettings;

my $log = Slim::Utils::Log->addLogCategory({
    'category' => 'plugin.resetvolume',
	'defaultLevel' => 'ERROR',
	'description' => 'PLUGIN_RESETVOLUME'
});

my $prefs = preferences('plugin.resetvolume');
my $sPrefs = preferences('server');

sub getDisplayName {
	return 'PLUGIN_RESETVOLUME';
}

my @browseMenuChoices = (
    'PLUGIN_RESETVOLUME_ENABLE',
	'PLUGIN_RESETVOLUME_SELECT_VOLUME',
	'PLUGIN_RESETVOLUME_RAISE',
);
my %menuSelection;

my %defaults = (
    'enabled'       => 0,
	'allowRaise'	=> 1,
	'volume'       	=> $Slim::Player::Player::defaultPrefs->{'volume'},
);


sub initPlugin {
	my $class = shift;
    $class->SUPER::initPlugin(@_);
	Plugins::ResetVolume::PlayerSettings->new();

	Slim::Control::Request::subscribe(\&setVolume, [['power']]);
}

sub shutdownPlugin {
	Slim::Control::Request::unsubscribe(\&setVolume);
}

sub setVolume {
	my $request = shift;
	my $client = $request->client();
	return unless defined $client;			# has to be a client.  Weird if not here.

	$log->debug("setVolume called for client " . $client->name());

	my $cPrefs = $prefs->client($client);

	# Only move on if we're alive
	return unless ($cPrefs->get('enabled'));

	# If power is being turned off, we're really not interested in setting the volume.
	return unless $client->power();


	my $alarm = Slim::Utils::Alarm->getCurrentAlarm($client);
	return if defined $alarm;				# If we're in an alarm, defer to it's value

	my $volume = $cPrefs->get('volume');

	if (!$cPrefs->get('allowRaise')) {
		# Can't just ask the player what the volume is, because at power on, if playing
		# is set, volume quickly fades from 0 to the previous volume, and we can get the
		# temporary value in the middle of the slide.
		#my $curVolume = $client->volume();
		my $curVolume = $sPrefs->client($client)->get('volume');
		$log->debug("allowRaise disabled.  Current: " . $curVolume . " Target: " . $volume);
		return if ($curVolume <= $volume);
	}

	$log->debug("Setting volume for " . $client->name() . " to $volume");
	$client->execute(["mixer", "volume", $volume]);
}

sub setMode {
    my $class = shift;
    my $client = shift;
	
	$menuSelection{$client} = 0 unless defined $menuSelection{$client};
	setDefaults($client, 0);

	$client->lines(\&lines);
}
        
sub lines {
    my $client = shift;
    my ($line1, $line2, $overlay2);
	my $flag;

    $line1 = $client->string('PLUGIN_RESETVOLUME') . " (" . ($menuSelection{$client}+1) . " " . $client->string('OF') . " " . ($#browseMenuChoices + 1) . ")";
	$line2	  = $client->string($browseMenuChoices[$menuSelection{$client}]);

	# Add a checkbox
    if ($browseMenuChoices[$menuSelection{$client}] eq 'PLUGIN_RESETVOLUME_ENABLE') {
        $flag  = $prefs->client($client)->get('enabled');
		$overlay2 = Slim::Buttons::Common::checkBoxOverlay($client, $flag);
    } elsif ($browseMenuChoices[$menuSelection{$client}] eq 'PLUGIN_RESETVOLUME_RAISE') {
        $flag  = $prefs->client($client)->get('allowRaise');
		$overlay2 = Slim::Buttons::Common::checkBoxOverlay($client, $flag);
	}

    return { 
		'line'		=> [ $line1, $line2],
		'overlay'	=> [undef, $overlay2],
	};
}

my %functions = (
	'up' => sub  {
		my $client = shift;
		my $newposition = Slim::Buttons::Common::scroll($client, -1, ($#browseMenuChoices + 1), $menuSelection{$client});
		$menuSelection{$client} =$newposition;
		$client->update();
	},
	'down' => sub  {
		my $client = shift;
		my $newposition = Slim::Buttons::Common::scroll($client, +1, ($#browseMenuChoices + 1), $menuSelection{$client});
		$menuSelection{$client} =$newposition;
		$client->update();
	},
	'right' => sub {
		my $client = shift;
		my $cPrefs = $prefs->client($client);
		my $selection = $menuSelection{$client};

		if ($browseMenuChoices[$selection] eq 'PLUGIN_RESETVOLUME_ENABLE')
		{
			my $enabled = $cPrefs->get('enabled') || 0;
			$client->showBriefly({ 'line1' => string('PLUGIN_RESETVOLUME'), 
								   'line2' => string($enabled ? 'PLUGIN_RESETVOLUME_DISABLING' :
																'PLUGIN_RESETVOLUME_ENABLING') });
			$cPrefs->set('enabled', ($enabled ? 0 : 1));
		} elsif ($browseMenuChoices[$selection] eq 'PLUGIN_RESETVOLUME_RAISE') {
			my $allowRaise = $cPrefs->get('allowRaise') || 0;
			$client->showBriefly({ 'line1' => string('PLUGIN_RESETVOLUME'), 
								   'line2' => string($allowRaise ? 'PLUGIN_RESETVOLUME_DISALLOWING_RAISE' :
																   'PLUGIN_RESETVOLUME_ALLOWING_RAISE') });
			$cPrefs->set('allowRaise', ($allowRaise ? 0 : 1));
		} elsif ($browseMenuChoices[$selection] eq 'PLUGIN_RESETVOLUME_SELECT_VOLUME')
		{
			adjustVolume($client);
		}
	},
	'left' => sub {
		my $client = shift;
		Slim::Buttons::Common::popModeRight($client);
	},
);

my %volume;
sub adjustVolume {
	my $client = shift;
	$volume{$client} = $prefs->client($client)->get('volume');

	$log->debug('Adjusting volume for ' . $client->name());

	my %params = (
		headerArgs      => 'C',
		header          => sub {
			# When using a single line display, only the header is shown and
			# may not fit the client name plus the volume level
				$client->string('PLUGIN_RESETVOLUME_VOLUME');
				},
		headerValueArgs => 'V',
		headerValue     => sub { return $client->volumeString($_[0]) },
		valueRef        => \$volume{$client},
		increment       => 1,
		onChangeArgs	=> 'V',
		onChange		=> sub {
								# $log->debug("Setting client " . $client->name() . " reset volume to " . $volume{$client});
								$prefs->client($client)->set('volume', $volume{$client});
						   },
	);
	Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Volume', \%params);
}

sub setDefaults {
    my $client = shift;
    my $force = shift;
    my $clientPrefs = $prefs->client($client);
    $log->debug("Checking defaults for " . $client->name() . " Forcing: " . $force);
    foreach my $key (keys %defaults) {
        if (!defined($clientPrefs->get($key)) || $force) {
            $log->debug("Setting default value for $key: " . $defaults{$key});
            $clientPrefs->set($key, $defaults{$key});
        }
    }
}

# Hack.  External version.  Called with class as first argument.  Yuck.
sub extSetDefaults {
	my $class = shift;          ## Get rid of this
	my $client = shift;
	my $force = shift;
	setDefaults($client, $force);
}

sub getFunctions { return \%functions;}
        
1;
