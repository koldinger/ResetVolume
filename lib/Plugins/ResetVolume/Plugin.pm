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


use vars qw($VERSION);
$VERSION = "0.1";

use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Log;

my $log = Slim::Utils::Log->addLogCategory({
    'category' => 'plugin.resetvolume',
	'defaultLevel' => 'ERROR',
	'description' => 'PLUGIN_RESETVOLUME'
});

my $prefs = preferences('plugin.resetvolume');

sub getDisplayName {
	return 'PLUGIN_RESETVOLUME';
}

my @browseMenuChoices = (
    'PLUGIN_RESETVOLUME_ON_OFF',       ## Keep this first.
	'PLUGIN_RESETVOLUME_SELECT_VOLUME',
);
my %menuSelection;

my %defaults = (
    'enabled'       => 0,               # Off by default
	'volume'       	=> 100,				# max volume
);


sub initPlugin {
	my $class = shift;
    $class->SUPER::initPlugin(@_);
	Slim::Control::Request::subscribe(\&setVolume, [['power']]);
}

sub shutdownPlugin {
	Slim::Control::Request::unsubscribe(\&setVolume);
}

sub setVolume {
	my $request = shift;
	my $client = $request->client();

	if (defined($client) && $prefs->client($client)->get('enabled'))
	{
		my $volume = $prefs->client($client)->get('volume');
		$log->debug("Setting volume for " . $client->name() . " to $volume");
		$client->execute(["mixer", "volume", $volume]);
	}
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

    $line1 = $client->string('PLUGIN_RESETVOLUME') . " (" . ($menuSelection{$client}+1) . " " . $client->string('OF') . " " . ($#browseMenuChoices + 1) . ")";

    if ($menuSelection{$client} != 0) {
        $line2 = $client->string($browseMenuChoices[$menuSelection{$client}]);
    } else {
        my $flag = $prefs->client($client)->get('enabled');
		$line2 = $client->string($flag ?  'PLUGIN_RESETVOLUME_DISABLE' : 'PLUGIN_RESETVOLUME_ENABLE');
    }

    return { 'line1' => $line1, 'line2' => $line2 };
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
		if ($browseMenuChoices[$selection] eq 'PLUGIN_RESETVOLUME_ON_OFF')
		{
			my $enabled = $cPrefs->get('enabled') || 0;
			$client->showBriefly({ 'line1' => string('PLUGIN_RESETVOLUME'), 
								   'line2' => string($enabled ? 'PLUGIN_RESETVOLUME_DISABLING' :
																'PLUGIN_RESETVOLUME_ENABLING') });
			$cPrefs->set('enabled', ($enabled ? 0 : 1));
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
				($client->linesPerScreen() != 1 ?  $client->name(). ' ' : '')
				. $client->string('PLUGIN_RESETVOLUME_SELECT_VOLUME');
				},
		headerValueArgs => 'V',
		headerValue     => sub { return $client->volumeString($_[0]) },
		valueRef        => \$volume{$client},
		increment       => 1,
		onChangeArgs	=> 'V',
		onChange		=> sub {
								$prefs->client($client)->set('volume', $_[0]);
						   },
	);
	Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Bar', \%params);
}

sub setDefaults {
    my $client = shift;
    my $force = shift;
    my $clientPrefs = $prefs->client($client);
    $log->debug("Checking defaults for " . $client->name());
    foreach my $key (keys %defaults) {
        if (!defined($clientPrefs->get($key)) || $force) {
            $log->debug("Setting default value for $key: " . $defaults{$key});
            $clientPrefs->set($key, $defaults{$key});
        }
    }
}

sub getFunctions { return \%functions;}
        
1;
