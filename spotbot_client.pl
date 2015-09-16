#!/user/bin/perl -w

# note: #!/usr/local/bin/perl -w for non mac users
#
# --------
# SPOTBOT
# --------
# Music Recommendation Feature, built on top of the Spotify API, and the EchoNest API.
#
# 	Built by:
#		Samantha Siow, 
#		ssiow1@jhu.edu, 
#		May 14th 2015
#
# For CS466 Information Retrieval and Web Agents at Johns Hopkins University.
#
# Example:
#
#    spotbot.pl
#
# Please read the README before running!
# 

use strict;
use lib '/Library/Perl/5.16/WebService';

use JSON qw( decode_json );
use HTTP::Request;
use HTTP::Response;
use LWP::UserAgent;
use Data::Dumper;

use WWW::Spotify;
use WWW::TheEchoNest::Artist;
use WWW::TheEchoNest::Song;
use WWW::TheEchoNest::Track;

# holds playlist objects returned from
# the user's spotify account
my @playlists = ( );

# profile for all liked tracks
my %liked_profile = ( );

# profile for all disliked tracks
my %disliked_profile = ( );

# vector holding all tracks in the liked playlist. accessible using the track
# number in the playlist, and is an array of hashes containing the track attributes.
my @liked_vector = ( );

# vector holding all tracks in the disliked playlist. accessible using the track
# number in the playlist, and is an array of hashes containing the track attributes.
my @disliked_vector = ( );

# index corresponds to the playlist id, and the value is 1 if it is a liked
# playlist, and 0 if it is not.
my @playlist_sense = ( );

# vector holding all tracks in the query playlist. accessible using the track
# number in the playlist, and is an array of hashes containing the track attributes.
my @query_vector = ( );

my $ua;

# using WWW::Spotify
my $spotify;
my $spotify_api_key = '2ee3b6f7fa4f43aaaee447aa3fc3ef43';
my $spotify_secret_key = 'eb08103e002e4b9e92319f55e24c0980';

# using WWW::TheEchoNest
my $echonest_song;
my $echonest_artist;
my $echonest_track;
my $echonest_api_key = 'TBFJ9IZF4ZF6IUV7R';

my $username;

&main_loop;

# Initialize all vectors using the liked and disliked playlists that
# have been provided by the user.

sub init_doc_vectors {
	my $liked_index = shift;
	my $disliked_index = shift;

	my $liked_id = $playlists[ $liked_index ]->{ 'id' };
	my $disliked_id = $playlists[ $disliked_index ]->{ 'id' };

	# use the perl wrapper to return the playlist tracks from the liked playlist
	my $liked_playlist = $spotify->get_playlist_tracks( $username , $liked_id );

	# decode the json
	my @liked_tracks = @{ decode_json( $liked_playlist )->{ 'tracks' }{ 'items' } };

	my $track_num = 0;

	# for each track in the playlist
	foreach my $tracks ( @liked_tracks ) {

		my @artists = @{ $tracks->{ 'track' }->{ 'artists' } };

		# add all the artists and genres associated with this song
		# to the liked vector hash
		foreach my $artist ( @artists ) {
			my $name = $artist->{'name'};
			my $artist_id =  $artist->{'id'};

			my $spotify_artist = decode_json( $spotify->artist( $artist_id ) );

			my @genres = @{ $spotify_artist->{'genres'} };

			foreach my $genre ( @genres ) {
				if ( defined $liked_vector[ $track_num ]{ $genre } ) {
					$liked_vector[ $track_num ]{ $genre } += 1;
				} else {
					$liked_vector[ $track_num ]{ $genre } = 1;
				}
			}

			if ( defined $liked_vector[ $track_num ]{ $name } ) {
				$liked_vector[ $track_num ]{ $name } += 1;
			} else {
				$liked_vector[ $track_num ]{ $name } = 1;
			}
		}

		# get the name of the track
		my $track_title = $tracks->{ 'track' }->{ 'name' };
		# get the artist name
		my $artist_name = $tracks->{ 'track' }->{ 'artists' }[0]->{'name'};

		# use the echo nest api to return information about the track
		my $song_raw = $echonest_song->search(  title => $track_title,
												artist => $artist_name );

		my $song_decoded = decode_json( $song_raw );

		# check the request code to see whether the get request was successful.
		my $response_code = $song_decoded->{'response'}->{'status'}->{'code'};

		# only allowed 20 calls a minute, and if over, throws error code 3
		# therefore, program sleeps for 60 seconds and attempts again
		if ( $response_code == 3 ) { 
			sleep(60);
			$song_raw = $echonest_song->search(  title => $track_title,
												 artist => $artist_name );

			$song_decoded = decode_json( $song_raw );
			$response_code = $song_decoded->{'response'}->{'status'}->{'code'};
		}
		
		if ( $response_code != 0 ) { print "Error $response_code retrieving song!\n"; next; }

		# get the id of the song in the echo nest api because it is not the same
		# as the song id from the spotify api
		my $song_id = $song_decoded->{'response'}->{'songs'}[0]->{'id'};

		# if not found, skip
		next if !defined $song_id;

		# prepare url for get request to echonest api
		my $url = "http://developer.echonest.com/api/v4/song/profile?api_key=";

			$url .= $echonest_api_key;

			$url .= "&id=";

			$url .= $song_id;

			$url .= "&bucket=audio_summary";

		# send get request
		my $request  = new HTTP::Request 'GET' => $url;
		my $response = $ua->request( $request );

		my $track_decoded = decode_json( $response->content );

		$response_code = $track_decoded->{'response'}->{'status'}->{'code'};

		# only allowed 20 calls a minute, and if over, throws error code 3
		# therefore, program sleeps for 60 seconds and attempts again
		if ( $response_code == 3 ) { 
			sleep(60);
			$request  = new HTTP::Request 'GET' => $url;
			$response = $ua->request( $request );

			$track_decoded = decode_json( $response->content );
			$response_code = $track_decoded->{'response'}->{'status'}->{'code'};
		}

		if ( $response_code != 0 ) { print "Error $response_code retrieving track!\n"; next; }

		# audio summary json object contains track information which we initialize in the hash
		# for this particular song.
		my $audio_summary = $track_decoded->{'response'}->{'songs'}[0]->{'audio_summary'};

		$liked_vector[ $track_num ]{ 'energy' } = $audio_summary->{ 'energy' };
		$liked_vector[ $track_num ]{ 'loudness' } = $audio_summary->{ 'loudness' };
		$liked_vector[ $track_num ]{ 'tempo' } = $audio_summary->{ 'tempo' };
		$liked_vector[ $track_num ]{ 'key' } = $audio_summary->{ 'key' };
		$liked_vector[ $track_num ]{ 'acousticness' } = $audio_summary->{ 'acousticness' };
		$liked_vector[ $track_num ]{ 'liveness' } = $audio_summary->{ 'liveness' };
		$liked_vector[ $track_num ]{ 'danceability' } = $audio_summary->{ 'danceability' };
		$liked_vector[ $track_num ]{ 'speechiness' } = $audio_summary->{ 'speechiness' };
		$liked_vector[ $track_num ]{ 'mode' } = $audio_summary->{ 'mode' };
		$liked_vector[ $track_num ]{ 'time_signature' } = $audio_summary->{ 'time_signature' };

		$track_num += 1;
	}

	# do the same for the disliked playlist
	my $disliked_playlist = $spotify->get_playlist_tracks( $username , $disliked_id );
	my @disliked_tracks = @{ decode_json( $disliked_playlist )->{ 'tracks' }{ 'items' } };

	$track_num = 0;

	foreach my $tracks ( @disliked_tracks ) {

		my @artists = @{ $tracks->{ 'track' }->{ 'artists' } };

		# add artists and genres associated with the song to the associative array
		foreach my $artist ( @artists ) {
			my $name = $artist->{'name'};
			my $artist_id =  $artist->{'id'};

			my $spotify_artist = decode_json( $spotify->artist( $artist_id ) );

			my @genres = @{ $spotify_artist->{'genres'} };

			foreach my $genre ( @genres ) {
				if ( defined $disliked_vector[ $track_num ]{ $genre } ) {
					$disliked_vector[ $track_num ]{ $genre } += 1;
				} else {
					$disliked_vector[ $track_num ]{ $genre } = 1;
				}
			}

			if ( defined $disliked_vector[ $track_num ]{ $name } ) {
				$disliked_vector[ $track_num ]{ $name } += 1;
			} else {
				$disliked_vector[ $track_num ]{ $name } = 1;
			}
		}


		my $track_title = $tracks->{ 'track' }->{ 'name' };
		my $artist_name = $tracks->{ 'track' }->{ 'artists' }[0]->{'name'};

		# get echonest song
		my $song_raw = $echonest_song->search(  title => $track_title,
											artist => $artist_name );


		my $song_decoded = decode_json( $song_raw );

		# only allowed 20 calls a minute, and if over, throws error code 3
		# therefore, program sleeps for 60 seconds and attempts again
		my $response_code = $song_decoded->{'response'}->{'status'}->{'code'};
		if ( $response_code == 3 ) { 
			sleep(60);
			$song_raw = $echonest_song->search(  title => $track_title,
												 artist => $artist_name );

			$song_decoded = decode_json( $song_raw );
			$response_code = $song_decoded->{'response'}->{'status'}->{'code'};
		}
		if ( $response_code != 0 ) { print "Error $response_code retrieving song!\n"; next; }

		my $song_id = $song_decoded->{'response'}->{'songs'}[0]->{'id'};
		next if !defined $song_id;

		my $url = "http://developer.echonest.com/api/v4/song/profile?api_key=";

			$url .= $echonest_api_key;

			$url .= "&id=";

			$url .= $song_id;

			$url .= "&bucket=audio_summary";

		# get song information from echonest api
		my $request  = new HTTP::Request 'GET' => $url;
		my $response = $ua->request( $request );

		my $track_decoded = decode_json( $response->content );
		
		$response_code = $track_decoded->{'response'}->{'status'}->{'code'};

		# only allowed 20 calls a minute, and if over, throws error code 3
		# therefore, program sleeps for 60 seconds and attempts again
		if ( $response_code == 3 ) { 
			sleep(60);
			$request  = new HTTP::Request 'GET' => $url;
			$response = $ua->request( $request );

			$track_decoded = decode_json( $response->content );
			$response_code = $track_decoded->{'response'}->{'status'}->{'code'};
		}

		if ( $response_code != 0 ) { print "Error $response_code retrieving track!\n"; next; }

		my $audio_summary = $track_decoded->{'response'}->{'songs'}[0]->{'audio_summary'};

		# add to associative array for the disliked songs
		$disliked_vector[ $track_num ]{ 'energy' } = $audio_summary->{ 'energy' };
		$disliked_vector[ $track_num ]{ 'loudness' } = $audio_summary->{ 'loudness' };
		$disliked_vector[ $track_num ]{ 'tempo' } = $audio_summary->{ 'tempo' };
		$disliked_vector[ $track_num ]{ 'key' } = $audio_summary->{ 'key' };
		$disliked_vector[ $track_num ]{ 'acousticness' } = $audio_summary->{ 'acousticness' };
		$disliked_vector[ $track_num ]{ 'liveness' } = $audio_summary->{ 'liveness' };
		$disliked_vector[ $track_num ]{ 'danceability' } = $audio_summary->{ 'danceability' };
		$disliked_vector[ $track_num ]{ 'speechiness' } = $audio_summary->{ 'speechiness' };
		$disliked_vector[ $track_num ]{ 'mode' } = $audio_summary->{ 'mode' };
		$disliked_vector[ $track_num ]{ 'time_signature' } = $audio_summary->{ 'time_signature' };

		$track_num += 1;
	}

}

sub main_loop {
	my $ROBOT_NAME = 'SpotBot/1.0';
	my $ROBOT_MAIL = 'ssiow1@jhu.edu';


	$ua = new LWP::UserAgent;  # create an new LWP::UserAgent
	$ua->agent( $ROBOT_NAME );    # identify who we are
	$ua->from ( $ROBOT_MAIL );    # and give an email address in case anyone would
	                              # like to complain

	# create the spotify agent
	$spotify = WWW::Spotify->new();

	# authorize spotify
	$spotify->oauth_client_id( $spotify_api_key );
	$spotify->oauth_client_secret( $spotify_secret_key );

	# create & authorize theechonest perl wrapper
	$echonest_song = WWW::TheEchoNest::Song->new( api_key => $echonest_api_key );
	$echonest_artist = WWW::TheEchoNest::Artist->new( api_key => $echonest_api_key );
	$echonest_track = WWW::TheEchoNest::Track->new( api_key => $echonest_api_key );



print <<"EndOfMenu";

	============================================================
	==     Welcome to 600.466 SpotBot Music Recommendation!
	==			(using the Spotify & EchoNest APIs)
	==
	==			by Samantha Siow (ssiow1\@jhu\.edu)                   
	============================================================

EndOfMenu
	;

	print "\tPlease enter your Spotify Username: (default is admin)\n\t";

	$username = <STDIN>;
	chomp $username;
	if ( $username eq "" ) { $username = 'disastache'; }

	if ( defined decode_json( $spotify->user( $username ) )->{'error'} ) {
		print "\n\tUser not found! Defaulting to admin...\n\n";
		$username = 'disastache';
	}

	print "\t. . . Retrieving Playlists . . .\n\n";

	my $result = $spotify->user_playlist($username);
	my $decoded_json = decode_json( $result );

	@playlists = @{ $decoded_json->{ 'items' } };

	if ( scalar @playlists < 2 ) { print "You need at least 2 playlists! Exiting program... \n"; exit 0;}

	my $counter = 0;

	print "\t-------------------------------------------------------\n";
	print "\tYour Playlists:\n";
	print "\t--------------------------------------------------------\n";

	foreach my $playlist_name ( @playlists ) {
		if ( $counter > 11 ) { last; }
		binmode(STDOUT, ":utf8"); # incase wide characters show
		print "\t" . $counter . ".\t" . $playlist_name->{ 'name' } . "\n";
		if ( $playlist_name->{ 'name' } =~ m/Y/ ) { push @playlist_sense, 1; } else { push @playlist_sense, 0; }
		$counter += 1;
	}

	print "\n\tIn order to provide accurate recommendations, please provide\n";
	print "\ta playlist of songs you like, and another of songs you dislike.\n\n";

	print "\tEnter the ID of the playlist containing songs you like: (default = 0) ";

	my $liked_id = <STDIN>;
	chomp $liked_id;
	if ( $liked_id eq '' or $liked_id > $counter ) { $liked_id = '0'; }

	print "\tEnter the ID of the playlist containing songs you dislike: (default = 1) ";

	my $disliked_id = <STDIN>;
	chomp $disliked_id;
	if ( $disliked_id eq '' or $disliked_id > $counter ) { $disliked_id = '1'; }

	print "\t. . . Initializing vector profiles for Playlist $liked_id and Playlist $disliked_id. . .\n\n";

		## TODO: Check if the playlists are empty

	&init_doc_vectors( $liked_id, $disliked_id );
	&init_profiles;

	while ( 1 ) {

	print <<"EndOfMenu";

	Select playlist with songs to classify!
	============================================================

EndOfMenu
    ;

    $counter = 0;

	foreach my $playlist_name ( @playlists ) {
		if ( $counter > 11 ) { last; }
		binmode(STDOUT, ":utf8"); # incase wide characters show
		print "\t" . $counter . ".\t" . $playlist_name->{ 'name' } . "\n";
		$counter += 1;
	}

		print "\tEnter Playlist ID number: ";

		my    $playlist_num = <STDIN>;
		chomp $playlist_num;

		&init_query_vectors( $playlist_num );

		print "\n\n";

		my $doc_num = 0;
		my $num_liked = 0;
		my $num_disliked = 0;

		my $sense = 0;
		print "\t---------------------------------------------------------------\n";
		print "\t\t\tSIM_LIKED\t\t\tSIM_DISLIKED\t\t\n";
		print "\t---------------------------------------------------------------\n";

		while ( defined $query_vector[$doc_num] ) {
			my $sim_l = &cosine_sim_a( \%liked_profile, $query_vector[ $doc_num ] );
			my $sim_d = &cosine_sim_a( \%disliked_profile, $query_vector[ $doc_num ] );
			print "\t";

			if ( $sim_l > $sim_d ) {
				print "+\t";
				$num_liked += 1;
			} else {
				print "\-\t";
				$num_disliked += 1;
			}

			print "\t$sim_l\t\t$sim_d\n";
			$doc_num += 1;
		}

		my $percentage_liked = 100 * $num_liked / ( $num_liked + $num_disliked );
		my $percentage_disliked = 100 * $num_disliked / ( $num_liked + $num_disliked );
		print "\n";
		print "\t----------------------------------------------------------------------------\n";
		print "\tWe think you will like $percentage_liked\% of this playlist,\n";
		print "\tand dislike $percentage_disliked\% of this playlist.\n";
		print "\t----------------------------------------------------------------------------\n";

		print "\tACTUAL PLAYLIST SENSE: ";

		if ( $playlist_sense[$playlist_num] == 1 ) {
			print "\tLiked\n";
			print "\tACCURACY: " . $percentage_liked . "\%";
		} else {
			print "\tDisliked\n";
			print "\tACCURACY: " . $percentage_disliked . "\%";
		}

		print "\n\n";

	}

}

sub init_query_vectors {
	my $index = shift;

	my $query_id = $playlists[ $index ]->{ 'id' };

	my $query_playlist = $spotify->get_playlist_tracks( $username , $query_id );
	my @query_tracks = @{ decode_json( $query_playlist )->{ 'tracks' }{ 'items' } };

	my $track_num = 0;

	foreach my $tracks ( @query_tracks ) {

		my $track_title = $tracks->{ 'track' }->{ 'name' };
		my @artists = @{ $tracks->{ 'track' }->{ 'artists' } };
		my $artist_name = $tracks->{ 'track' }->{ 'artists' }[0]->{'name'};

		foreach my $artist ( @artists ) {
			my $name = $artist->{'name'};
			my $artist_id =  $artist->{'id'};

			my $spotify_artist = decode_json( $spotify->artist( $artist_id ) );

			my @genres = @{ $spotify_artist->{'genres'} };

			foreach my $genre ( @genres ) {
				if ( defined $query_vector[ $track_num ]{ $genre } ) {
					$query_vector[ $track_num ]{ $genre } += 1;
				} else {
					$query_vector[ $track_num ]{ $genre } = 1;
				}
			}

			if ( defined $query_vector[ $track_num ]{ $name } ) {
				$query_vector[ $track_num ]{ $name } += 1;
			} else {
				$query_vector[ $track_num ]{ $name } = 1;
			}
		}

		my $song_raw = $echonest_song->search(  title => $track_title,
												artist => $artist_name );

		my $song_decoded = decode_json( $song_raw );

		
		my $response_code = $song_decoded->{'response'}->{'status'}->{'code'};

		# only allowed 20 calls a minute, and if over, throws error code 3
		# therefore, program sleeps for 60 seconds and attempts again
		if ( $response_code == 3 ) { 
			sleep(60);
			$song_raw = $echonest_song->search(  title => $track_title,
												 artist => $artist_name );

			$song_decoded = decode_json( $song_raw );
			$response_code = $song_decoded->{'response'}->{'status'}->{'code'};
		}
		
		if ( $response_code != 0 ) { print "Error $response_code retrieving song!\n"; next; }

		my $song_id = $song_decoded->{'response'}->{'songs'}[0]->{'id'};

		next if !defined $song_id;

		my $url = "http://developer.echonest.com/api/v4/song/profile?api_key=";

			$url .= $echonest_api_key;

			$url .= "&id=";

			$url .= $song_id;

			$url .= "&bucket=audio_summary";


		my $request  = new HTTP::Request 'GET' => $url;
		my $response = $ua->request( $request );

		my $track_decoded = decode_json( $response->content );

		$response_code = $track_decoded->{'response'}->{'status'}->{'code'};

		# only allowed 20 calls a minute, and if over, throws error code 3
		# therefore, program sleeps for 60 seconds and attempts again
		if ( $response_code == 3 ) { 
			sleep(60);
			$request  = new HTTP::Request 'GET' => $url;
			$response = $ua->request( $request );

			$track_decoded = decode_json( $response->content );
			$response_code = $track_decoded->{'response'}->{'status'}->{'code'};
		}

		if ( $response_code != 0 ) { print "Error $response_code retrieving track!\n"; next; }

		my $audio_summary = $track_decoded->{'response'}->{'songs'}[0]->{'audio_summary'};

		$query_vector[ $track_num ]{ 'energy' } = $audio_summary->{ 'energy' };
		$query_vector[ $track_num ]{ 'loudness' } = $audio_summary->{ 'loudness' };
		$query_vector[ $track_num ]{ 'tempo' } = $audio_summary->{ 'tempo' };
		$query_vector[ $track_num ]{ 'key' } = $audio_summary->{ 'key' };
		$query_vector[ $track_num ]{ 'acousticness' } = $audio_summary->{ 'acousticness' };
		$query_vector[ $track_num ]{ 'liveness' } = $audio_summary->{ 'liveness' };
		$query_vector[ $track_num ]{ 'danceability' } = $audio_summary->{ 'danceability' };
		$query_vector[ $track_num ]{ 'speechiness' } = $audio_summary->{ 'speechiness' };
		$query_vector[ $track_num ]{ 'mode' } = $audio_summary->{ 'mode' };
		$query_vector[ $track_num ]{ 'time_signature' } = $audio_summary->{ 'time_signature' };

		$track_num += 1;
	}


}

# print 'URI: ' . $text->{ 'uri' } . "\n";



#
# create a request object associating the 'GET' method with the URL we
# want to connect to. Then have the UserAgent contact the web server and
# return the server's response.
#

# my $request  = new HTTP::Request 'GET' => "$ARGV[0]";
# my $request  = new HTTP::Request 'GET' => "https://api.spotify.com/v1/users/disastache/playlists";
# my $response = $ua->request( $request );

# 
# print out the header information and the unmodified content
# of the requested page.
#

#print $response->headers_as_string, "\n";
#print $response->content;


sub init_profiles {
	my $doc_num = 0;

	while ( defined $liked_vector[$doc_num] ){

		foreach my $track_attribute ( keys $liked_vector[$doc_num] ) {
			$liked_profile{ $track_attribute } += $liked_vector[$doc_num]{ $track_attribute};
		}

		$doc_num += 1;
	}

	$doc_num = 0;
	while ( defined $disliked_vector[$doc_num] ){

		foreach my $track_attribute ( keys $disliked_vector[$doc_num] ) {

			$disliked_profile{ $track_attribute } += $disliked_vector[$doc_num]{ $track_attribute};
		}

		$doc_num += 1;
	}

	my $liked_length = scalar @liked_vector;
	my $disliked_length = scalar @disliked_vector;

	foreach my $track_attribute ( keys %{ $liked_vector[$doc_num] }) {

		$liked_profile{ $track_attribute } /= $liked_length;
	}

	foreach my $track_attribute ( keys {$disliked_vector[$doc_num]} ) {

		$disliked_profile{ $track_attribute } /= $disliked_length;
	}

}


########################################################
## COSINE_SIM_A
## 
## Computes the cosine similarity for two vectors
## represented as associate arrays.
########################################################

sub cosine_sim_a {

    my $vec1 = shift;
    my $vec2 = shift;

    # reset and init to 0
    my $cross_prod     = 0;
    my $sum_sq1 = 0;
    my $sum_sq2 = 0;

    my @val1 = values $vec1;
    my @val2 = values %{ $vec2 };

    # determine shortest length vector. This should speed 
    # things up if one vector is considerable longer than
    # the other (i.e. query vector to document vector).

    if ((scalar @val1) > (scalar @val2)) {
	my $tmp  = $vec1;
	   $vec1 = $vec2;
	   $vec2 = $tmp;
    }

    # calculate the cross product

    my $key = undef;
    my $val = undef;

    while (($key, $val) = each %{ $vec1 }) {
		$cross_prod += $val * ($$vec2{ $key } || 0);
    }

    # calculate the sum of squares

    my $term = undef;

    foreach $term (@val1) { $sum_sq1 += $term * $term; }
    foreach $term (@val2) { $sum_sq2 += $term * $term; }

    if ( $sum_sq1 * $sum_sq2 == 0 ) {
    	return 0;
    }
    return ( $cross_prod / sqrt( $sum_sq1 * $sum_sq2 )) ;
}

