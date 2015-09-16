package WWW::TheEchoNest;

use Moose;

BEGIN {
    $WWW::TheEchoNest::VERSION = "1.1";
}

use Data::Dumper;
use URI;
use URI::Escape;
use WWW::Mechanize;
use JSON::XS;
use JSON::Path;
use XML::Simple;
use HTTP::Headers;
use Scalar::Util;
use File::Basename;
use IO::CaptureOutput qw( capture qxx qxy );
use Digest::MD5::File qw( file_md5_hex url_md5_hex );
use WWW::TheEchoNest::Codegen;

# use File::Which (future work for auto finding ffmpeg program)
# use File::Fetch (assist with bringing remote data, http, ftp, etc)

# ABSTRACT: Wrapper for The Echo Nest API of music intelligence

has 'api_key' => (
    is       => 'rw',
    isa      => 'Str',
    required => 1,
);

has 'version' => (
    is       => 'rw',
    isa      => 'Str',
    default  => 'v4',
);

has 'result_format' => (
    is       => 'rw',
    isa      => 'Str',
    default  => 'json',
);

has 'results' => (
    is       => 'rw',
    isa      => 'Int',
    default  => '15'
);

has 'debug' => (
    is       => 'rw',
    isa      => 'Int',
    default  => 0,
);

has 'uri_scheme' => (
    is       => 'rw',
    isa      => 'Str',
    default  => 'http',
);

has uri_hostname => (
    is       => 'rw',
    isa      => 'Str',
    default  => 'developer.echonest.com'
);

has uri_domain_path => (
    is       => 'rw',
    isa      => 'Str',
    default  => 'api',
);

has call_type => (
    is       => 'rw',
    isa      => 'Str',
);

has auto_json_decode => (
    is       => 'rw',
    isa      => 'Int',
    default  => 0
);

has auto_xml_decode => (
    is       => 'rw',
    isa      => 'Int',
    default  => 0
);

has codegen_command => (
    is        => 'rw',
    isa       => 'Str',
    default   => q{}
);

has seed_limit => (
    is        => 'rw',
    isa       => 'Int',
    default   => '5'
);

has last_result => (
    is        => 'rw',
    isa       => 'Str',
    default   => q{}
);

has last_error => (
    is        => 'rw',
    isa       => 'Str',
    default   => q{}
);

has response_headers => (
    is        => 'rw',
    isa       => 'Str',
    default   => q{}
);

has problem => (
    is        => 'rw',
    isa       => 'Str',
    default   => q{}
);

my %code_to_name = (

'-1' =>	'Unknown Error',
0 =>	'Success',
1 =>	'Missing/ Invalid API Key',
2 =>	'This API key is not allowed to call this method',
3 =>	'Rate Limit Exceeded',
4 =>	'Missing Parameter',
5 =>	'Invalid Parameter'
);

# ADD CODE HERE TO READ A CONFIG FILE IN /etc or ~ depending on platform
# NOT HIGH PRIORITY (to original author)

# Intitial plan is to create this with type as the key
# and then a two element array as the value with
# element 1 being name and element 2 being if it is optional
# need to address the dependency model some how
# the third element is if it allows multiple values

my %call_type_attributes = ( 
  'artist/biographies' => [
        [ 'id|name' ,  1 ],
        [ 'format'  ,  0 ],
        [ 'callback' , 0 ],
        [ 'results',   0 ],
        [ 'start' ,    0 ],
        [ 'license' ,  0 , 1 ]
                            ],

   'artist/blogs' => [
        [ 'id|name'        , 1 ],
        [ 'format'         , 0 ],
        [ 'callback'       , 0 ],
        [ 'results'        , 0 ],
        [ 'start'          , 0 ],
        [ 'high_relevnace' , 0 ]
    
   ],

   'artist/familiarity' => [
        [ 'id|name'        , 1 ],
        [ 'format'         , 0 ],
        [ 'callback'       , 0 ],    
   ],
   
   'artist/hotttnesss' => [
        [ 'id|name'        , 1 ],
        [ 'format'         , 0 ],
        [ 'callback'       , 0 ],
        [ 'type'           , 0 ],
   ],
   
   'artist/images' => [
        [ 'id|name'        , 1 ],
        [ 'format'         , 0 ],
        [ 'callback'       , 0 ],
        [ 'results'        , 0 ],
        [ 'start'          , 0 ],
        [ 'license'        , 0 , 1 ],
   ],
   
   'artist/list_genres' => [
        [ 'format'         , 0 ],
        [ 'callback'       , 0 ],
   ],   
   
   'artist/list_terms' => [
        [ 'format'         , 0 ],
        [ 'callback'       , 0 ],
        [ 'type'           , 0 ]   
   ],   
   
   'artist/news' => [
        [ 'id|name'        , 1 ],
        [ 'format'         , 0 ],
        [ 'callback'       , 0 ],
        [ 'results'        , 0 ],
        [ 'start'          , 0 ],
        [ 'high_relevnace' , 0 ]
    
   ],

   'artist/profile' => [
        [ 'id|name'        , 1 ],
        [ 'format'         , 0 ],
        [ 'callback'       , 0 ],
        [ 'bucket'         , 0 , 1 ],
   ],
   
   'artist/reviews' => [
        [ 'id|name'        , 1 ],
        [ 'format'         , 0 ],
        [ 'callback'       , 0 ],
        [ 'results'        , 0 ],
        [ 'start'          , 0 ],
   ],
   
   'artist/search' => [
        [ 'name'        , 0 ],
        [ 'format'         , 0 ],
        [ 'callback'       , 0 ],
        [ 'bucket', 0 , 1 ], 
        [ 'limit', 0  ], 
        [ 'artist_location', 0  ], 
        [ 'description', 0  ], 
        [ 'genre', 0 , 1 ], 
        [ 'style', 0 , 1 ], 
        [ 'mood', 0 , 1 ], 
        [ 'rank_type', 0  ], 
        [ 'fuzzy_match', 0  ], 
        [ 'max_familiarity', 0  ], 
        [ 'min_familiarity', 0  ], 
        [ 'max_hotttnesss', 0  ], 
        [ 'min_hotttnesss', 0  ], 
        [ 'artist_start_year_before', 0  ], 
        [ 'artist_start_year_after', 0  ], 
        [ 'artist_end_year_before', 0  ], 
        [ 'artist_end_year_after', 0  ], 
        [ 'sort', 0  ], 
        [ 'results', 0  ], 
        [ 'start', 0  ], 
    
   ],
   
    'artist/extract' => [
        [ 'format'         , 0 ],
        [ 'callback'       , 0 ],
        [ 'results'        , 0 ],
        [ 'bucket', 0 , 1  ], 
        [ 'limit', 0  ],
        [ 'text' , 0 ],
        [ 'max_familiarity', 0  ], 
        [ 'min_familiarity', 0  ], 
        [ 'max_hotttnesss', 0  ], 
        [ 'min_hotttnesss', 0  ],     
        [ 'sort'           , 0 ],
        [ 'results' , 0 ]
    
   ],

   'artist/songs' => [
        [ 'id|name'        , 1 ],
        [ 'format'         , 0 ],
        [ 'callback'       , 0 ],
        [ 'results'        , 0 ],
        [ 'start'          , 0 ]
   ],
   
   'artist/similar' => [
        [ 'id|name'        , 1 , 1 ],
        [ 'format'         , 0 ],
        [ 'callback'       , 0 ],
        [ 'results'        , 0 ],
        [ 'min_results'        , 0 ],
        [ 'start'          , 0 ],
        [ 'bucket', 0 , 1 ], 
        [ 'limit', 0  ], 
        [ 'artist_location', 0  ], 
        [ 'name', 0  ], 
        [ 'description', 0  ], 
        [ 'genre', 0  ], 
        [ 'style', 0  ], 
        [ 'mood', 0  ], 
        [ 'rank_type', 0  ], 
        [ 'fuzzy_match', 0  ], 
        [ 'max_familiarity', 0  ], 
        [ 'min_familiarity', 0  ], 
        [ 'max_hotttnesss', 0  ], 
        [ 'min_hotttnesss', 0  ], 
        [ 'artist_start_year_before', 0  ], 
        [ 'artist_start_year_after', 0  ], 
        [ 'artist_end_year_before', 0  ], 
        [ 'artist_end_year_after', 0  ], 
        [ 'seed_catalog', 0 , 1 ]
    
   ],
   
   'artist/suggest' => [
        [ 'name'           , 0 ],
        [ 'format'         , 0 ],
        [ 'callback'       , 0 ],
        [ 'results'        , 0 ],
        [ 'q'              , 0 ]
   ],   
   
   'artist/terms' => [
        [ 'id|name'        , 1 ],
        [ 'format'         , 0 ],
        [ 'callback'       , 0 ],
        [ 'sort'           , 0 ]    
   ],
   
   'artist/top_hottt' => [
        [ 'format'         , 0 ],
        [ 'callback'       , 0 ],
        [ 'results'        , 0 ],
        [ 'start'          , 0 ],
        [ 'genre'          , 0 ],
        [ 'bucket'         , 0 , 1 ],
        [ 'limit'          , 0 ]
   ],

   'artist/top_terms' => [
        [ 'format'         , 0 ],
        [ 'callback'       , 0 ],
        [ 'results'        , 0 ]
   ],
   
   'artist/twitter' => [
        [ 'id|name'        , 1 ],
        [ 'format'         , 0 ],
        [ 'callback'       , 0 ]    
   ],

   'artist/urls' => [
        [ 'id|name'        , 1 ],
        [ 'format'         , 0 ],
        [ 'callback'       , 0 ]
   
   ],

   'artist/video' => [
        [ 'id|name'        , 1 ],
        [ 'format'         , 0 ],
        [ 'callback'       , 0 ],
        [ 'results'        , 0 ],
        [ 'start'          , 0 ]
   ],
   
   # SONG PARAMETERS
   
    'song/search' => [
        [ 'format', 0  ],
        [ 'title', 0  ],
        [ 'artist', 0  ],
        [ 'combined', 0  ],
        [ 'description', 0 , 1 ],
        [ 'style', 0 , 1 ],
        [ 'mood', 0 , 1 ],
        [ 'rank_type', 0  ],
        [ 'artist_id', 0  ],
        [ 'results', 0  ],
        [ 'start', 0  ],
        [ 'song_type', 0 , 1 ],
        [ 'max_tempo', 0  ],
        [ 'min_tempo', 0  ],
        [ 'max_duration', 0  ],
        [ 'min_duration', 0  ],
        [ 'max_loudness', 0  ],
        [ 'min_loudness', 0  ],
        [ 'artist_max_familiarity', 0  ],
        [ 'artist_min_familiarity', 0  ],
        [ 'artist_start_year_before', 0  ],
        [ 'artist_start_year_after', 0  ],
        [ 'artist_end_year_before', 0  ],
        [ 'artist_end_year_after', 0  ],
        [ 'song_max_hotttnesss', 0  ],
        [ 'song_min_hotttnesss', 0  ],
        [ 'artist_max_hotttnesss', 0  ],
        [ 'artist_min_hotttnesss', 0  ],
        [ 'min_longitude', 0  ],
        [ 'max_longitude', 0  ],
        [ 'min_latitude', 0  ],
        [ 'max_latitude', 0  ],
        [ 'max_danceability', 0  ],
        [ 'min_danceability', 0  ],
        [ 'max_energy', 0  ],
        [ 'min_energy', 0  ],
        [ 'mode', 0  ],
        [ 'key', 0  ],
        [ 'bucket', 0 , 1 ],
        [ 'sort', 0  ],
        [ 'limit', 0  ]    
        
    ],

    'song/profile' => [
        [ 'id|track_id' , 1 ],
        [ 'format' , 0 ],
        [ 'bucket' , 0 , 1 ],
        [ 'limit'  , 0 ]
    ],
    
    'song/identify' => [
        [ 'query', 0  ],
        [ 'code', 0  ],
        [ 'artist', 0  ],
        [ 'title', 0  ],
        [ 'release', 0  ],
        [ 'duration', 0  ],
        [ 'genre', 0  ],
        [ 'version', 0  ],
        [ 'bucket', 0 , 1 ],
    ],
    
    # TRACK ATTRIBUTES
    
    'track/profile' => [
        [ 'id|md5' , 1 ],
        [ 'format'         , 0 ],
        [ 'callback'       , 0 ],
        [ 'bucket'         , 0 , 1 ]    
    ],
    
    'track/upload' => [
        [ 'format'         , 0 ],
        [ 'callback'       , 0 ],
        [ 'url|filetype'   , 1 ]
    ],
    
    # PLAYLIST PARAMETERS
    
    'playlist/basic' => [
        [ 'format', 0  ],
        [ 'callback', 0  ],
        [ 'type', 0  ],
        [ 'artist_id', 0 , 1 ],
        [ 'artist', 0 , 1 ],
        [ 'song_id', 0 , 1 ],
        [ 'genre', 0  ],
        [ 'track_id', 0 , 1 ],
        [ 'results', 0  ],
        [ 'bucket', 0 , 1 ],
        [ 'limit', 0  ],
        [ 'dmca', 0  ],
        [ 'limited_interactivity' , 0    ]
    ],
    
    'playlist/static' => [
        [ 'format', 0                    ],
        [ 'callback', 0                  ],
        [ 'type', 0                      ],
        [ 'artist_pick', 0               ],
        [ 'variety', 0                   ],
        [ 'distribution', 0              ],
        [ 'adventurousness', 0           ],
        [ 'artist_id', 0  , 1            ],
        [ 'artist', 0 , 1                ],
        [ 'seed_catalog', 0              ],
        [ 'song_id', 0 , 1               ],
        [ 'track_id', 0  , 1             ],
        [ 'genre' , 0                    ],
        
        # these are considered premium as of Sept 2013
        [ 'description', 0 , 1           ],
        [ 'style', 0  , 1                ],
        [ 'mood', 0   , 1                ],
        [ 'results', 0                   ],
        [ 'max_tempo', 0                 ],
        [ 'min_tempo', 0                 ],
        [ 'max_duration', 0              ],
        [ 'min_duration', 0              ],
        [ 'max_loudness', 0              ],
        [ 'min_loudness', 0              ],
        [ 'max_danceability', 0          ],
        [ 'min_danceability', 0          ],
        [ 'max_energy', 0                ],
        [ 'min_energy', 0                ],
        [ 'artist_max_familiarity', 0    ],
        [ 'artist_min_familiarity', 0    ],
        [ 'artist_max_hotttnesss', 0     ],
        [ 'artist_min_hotttnesss', 0     ],
        [ 'artist_start_year_before', 0  ],
        [ 'artist_start_year_after', 0   ],
        [ 'artist_end_year_before', 0    ],
        [ 'artist_end_year_after', 0     ],
        [ 'song_type', 0 , 1             ],
        [ 'song_max_hotttnesss', 0       ],
        [ 'song_min_hotttnesss', 0       ],
        [ 'min_longitude', 0             ],
        [ 'max_longitude', 0             ],
        [ 'min_latitude', 0              ],
        [ 'max_latitude', 0              ],
        [ 'mode', 0 , 1                  ],
        [ 'key', 0                       ],
        [ 'bucket', 0 , 1                ],
        [ 'sort', 0                      ],
        [ 'limit', 0                     ],
        [ 'dmca', 0                      ],
        [ 'limited_interactivity' , 0    ]
    ],
   'playlist/dynamic/create' => [
        [ 'session_catalog' , 0 , 1 ],
        [ 'format', 0  ],
        [ 'callback', 0  ],
        [ 'type', 0  ],
        [ 'artist_pick', 0  ],
        [ 'variety', 0  ],
        [ 'distribution', 0  ],
        [ 'adventurousness', 0  ],
        [ 'artist_id', 0  ],
        [ 'artist', 0  ],
        [ 'seed_catalog', 0  ],
        [ 'song_id', 0  ],
        [ 'track_id', 0  ],
        [ 'description', 0  ],
        [ 'style', 0  ],
        [ 'mood', 0  ],
        [ 'max_tempo', 0  ],
        [ 'min_tempo', 0  ],
        [ 'max_duration', 0  ],
        [ 'min_duration', 0  ],
        [ 'max_loudness', 0  ],
        [ 'min_loudness', 0  ],
        [ 'max_danceability', 0  ],
        [ 'min_danceability', 0  ],
        [ 'max_energy', 0  ],
        [ 'min_energy', 0  ],
        [ 'artist_max_familiarity', 0  ],
        [ 'artist_min_familiarity', 0  ],
        [ 'artist_max_hotttnesss', 0  ],
        [ 'artist_min_hotttnesss', 0  ],
        [ 'artist_start_year_before', 0  ],
        [ 'artist_start_year_after', 0  ],
        [ 'artist_end_year_before', 0  ],
        [ 'artist_end_year_after', 0  ],
        [ 'song_max_hotttnesss', 0  ],
        [ 'song_min_hotttnesss', 0  ],
        [ 'min_longitude', 0  ],
        [ 'max_longitude', 0  ],
        [ 'min_latitude', 0  ],
        [ 'max_latitude', 0  ],
        [ 'mode', 0  ],
        [ 'key', 0  ],
        [ 'bucket', 0 , 1 ],
        [ 'sort', 0  ],
        [ 'limit', 0  ],
        [ 'dmca', 0  ],
        [ 'genre', 0  ],
        [ 'limited_interactivity' , 0    ]
   ],
   
   'playlist/dynamic/restart' => [
        [ 'session_catalog' , 0 ],
        [ 'session_id' , 1 ],
        [ 'format', 0  ],
        [ 'callback', 0  ],
        [ 'type', 0  ],
        [ 'artist_pick', 0  ],
        [ 'variety', 0  ],
        [ 'distribution', 0  ],
        [ 'adventurousness', 0  ],
        [ 'artist_id', 0  ],
        [ 'artist', 0  ],
        [ 'seed_catalog', 0  ],
        [ 'song_id', 0  ],
        [ 'track_id', 0  ],
        [ 'description', 0  ],
        [ 'style', 0  ],
        [ 'mood', 0  ],
        [ 'results', 0  ],
        [ 'max_tempo', 0  ],
        [ 'min_tempo', 0  ],
        [ 'max_duration', 0  ],
        [ 'min_duration', 0  ],
        [ 'max_loudness', 0  ],
        [ 'min_loudness', 0  ],
        [ 'max_danceability', 0  ],
        [ 'min_danceability', 0  ],
        [ 'max_energy', 0  ],
        [ 'min_energy', 0  ],
        [ 'artist_max_familiarity', 0  ],
        [ 'artist_min_familiarity', 0  ],
        [ 'artist_max_hotttnesss', 0  ],
        [ 'artist_min_hotttnesss', 0  ],
        [ 'artist_start_year_before', 0  ],
        [ 'artist_start_year_after', 0  ],
        [ 'artist_end_year_before', 0  ],
        [ 'artist_end_year_after', 0  ],
        [ 'song_max_hotttnesss', 0  ],
        [ 'song_min_hotttnesss', 0  ],
        [ 'min_longitude', 0  ],
        [ 'max_longitude', 0  ],
        [ 'min_latitude', 0  ],
        [ 'max_latitude', 0  ],
        [ 'mode', 0  ],
        [ 'key', 0  ],
        [ 'bucket', 0  , 1 ],
        [ 'sort', 0  ],
        [ 'limit', 0  ],
        [ 'dmca', 0  ],
        [ 'limited_interactivity' , 0    ],
        [ 'genre', 0  ]
   ],
   
   'playlist/dynamic/next' => [
        [ 'format' ,    0 ],
        [ 'callback' ,  0 ],
        [ 'results' ,   0 ],
        [ 'lookahead' , 0 ],
        [ 'session_id' , 0 ]
   ],
   
   'playlist/dynamic/feedback' => [
        [ 'format', 0  ],
        [ 'callback', 0  ],
        [ 'ban_artist', 0  ],
        [ 'favorite_artist', 0  ],
        [ 'ban_song', 0  ],
        [ 'skip_song', 0  ],
        [ 'favorite_song', 0  ],
        [ 'play_song', 0  ],
        [ 'unplay_song', 0  ],
        [ 'rate_song', 0  ],
        [ 'update_catalog', 0  ],
        [ 'invalidate_song', 0  ],
        [ 'invalidate_artist', 0  ],
        [ 'session_id' , 0 ]
   ],
   
   'playlist/dynamic/steer' => [
        [ 'format', 0  ],
        [ 'callback', 0  ],
        [ 'min_xxx', 0  ],
        [ 'max_xxx', 0  ],
        [ 'target_xxx', 0  ],
        [ 'more_like_this', 0  ],
        [ 'less_like_this', 0  ],
        [ 'adventurousness', 0  ],
        [ 'variety', 0  ],
        [ 'description', 0  ],
        [ 'style', 0  ],
        [ 'song_type', 0  ],
        [ 'mood', 0  ],
        [ 'reset', 0  ],
        [ 'session_id' , 0 ]
   ],
   
   'playlist/dynamic/info' => [
        [ 'session_id' , 0 ],
        [ 'format', 0  ],
        [ 'callback', 0  ]
   ],

   'playlist/dynamic/delete' => [
        [ 'session_id' , 0 ],
        [ 'format', 0  ],
        [ 'callback', 0  ]
   ],

   # TASTE PROFILE PARAMETERS
    
    'tasteprofile/create' => [
        [ 'format', 0  ],
        [ 'callback', 0  ],
        [ 'name', 1  ],
        [ 'type', 1  ]
    ],
    
    'tasteprofile/update' => [
        [ 'format', 0  ],
        [ 'callback', 0  ],
        [ 'id', 1  ],
        [ 'data_type', 0  ],
        [ 'data' , 0 ]
    ],
    
    'tasteprofile/keyvalues' => [
        [ 'format', 0  ],
        [ 'callback', 0  ],
        [ 'id', 1  ],       
    ],
    
    'tasteprofile/play' => [
        [ 'format', 0  ],
        [ 'callback', 0  ],
        [ 'id', 1  ],  
        [ 'item', 1  ],
        [ 'plays', 0  ]       
    ],

    'tasteprofile/skip' => [
        [ 'format', 0  ],
        [ 'callback', 0  ],
        [ 'id', 1  ],  
        [ 'item', 1  ],
        [ 'skips', 0  ]       
    ],    

    'tasteprofile/favorite' => [
        [ 'format', 0  ],
        [ 'callback', 0  ],
        [ 'id', 1  ],  
        [ 'item', 1  ],
        [ 'favorite', 0  ]       
    ],
    
    'tasteprofile/ban' => [
        [ 'format', 0  ],
        [ 'callback', 0  ],
        [ 'id', 1  ],  
        [ 'item', 1  ],
        [ 'ban', 0  ]       
    ],
    
    'tasteprofile/rate' => [
        [ 'format', 0  ],
        [ 'callback', 0  ],
        [ 'id', 1  ],  
        [ 'item', 1  ],
        [ 'rating', 0  ]       
    ],

    'tasteprofile/status' => [
        [ 'format', 0  ],
        [ 'callback', 0  ],
        [ 'ticket', 1  ]       
    ],
    
    'tasteprofile/profile' => [
        [ 'format', 0  ],
        [ 'callback', 0  ],
        [ 'id|name', 1  ],  
    ],     
    
    'tasteprofile/read' => [
        [ 'format', 0  ],
        [ 'callback', 0  ],
        [ 'id', 1  ],  
        [ 'item_id', 0  ],
        [ 'bucket', 0 , 1 ],
        [ 'results' , 0 ],
        [ 'start' , 0 ]
    ],     

    'tasteprofile/feed' => [
        [ 'format', 0  ],
        [ 'callback', 0  ],
        [ 'id', 1  ],  
        [ 'bucket', 0 , 1 ],
        [ 'results' , 0 ],
        [ 'start' , 0 ],
        [ 'since' , 0 ],
        [ 'high_relevance' , 0 ]
    ],   

    'tasteprofile/delete' => [
        [ 'format', 0  ],
        [ 'callback', 0  ],
        [ 'id', 1  ]
    ],
    
    'tasteprofile/list' => [
        [ 'format', 0  ],
        [ 'callback', 0  ],
        [ 'results', 0  ],
        [ 'start' , 0 ]
    ],

    'tasteprofile/similar' => [
        [ 'format', 0  ],
        [ 'callback', 0  ],
        [ 'id', 1  ],
        [ 'results', 0  ],
        [ 'start' , 0 ],
        [ 'keyvalue' , 0 ]
    ],

    'tasteprofile/predict' => [
        [ 'format', 0  ],
        [ 'callback', 0  ],
        [ 'id', 1  ],
        [ 'category', 0  ]
    ],
    
    # SANDBOX PARAMETERS
    
    'sandbox/list' => [
        [ 'format', 0  ],
        [ 'callback', 0  ],
        [ 'sandbox', 1  ],
        [ 'results', 0  ],
        [ 'start' , 0 ],
    ],
    
    'sandbox/access' => [
        [ 'format', 0  ],
        [ 'callback', 0  ],
        [ 'sandbox', 0  ],
        [ 'id', 0  ],
        [ 'oauth_nonce', 0  ],
        [ 'oauth_timestamp', 0  ],
        [ 'oauth_version', 0  ],
        [ 'oauth_signature_method', 0  ],
        [ 'oauth_consumer_key', 0  ],
        [ 'oauth_signature', 0  ]        
    ],
);

# need to map tasteprofile calls to catalog for backward compatibility

foreach my $call_type ( keys %call_type_attributes ) {
    if ($call_type =~ /tasteprofile/) {
        my ($tp,$thecall) = split('/',$call_type);
        $call_type_attributes{'catalog/'.$thecall} = $call_type_attributes{$call_type};
    }
    
}

# Taken from WWW::Echonest for initial iteration

# Typenames that appear in Echonest identifier codes
my %typenames =
    (
     AR => 'artist',
     SO => 'song',
     RE => 'release',
     TR => 'track',
     PE => 'person',
     DE => 'device',
     LI => 'listener',
     ED => 'editor',
     TW => 'tweditor',
     CA => 'catalog',
    );

my $short_type = join (q{|}, keys %typenames);
my $long_type = join (q{|}, values %typenames);
    
# These regexes need better names!
my %id_regex_for =
    (
     # foreign regex example...
     # musicbrainz:artist:a74b1b7f-71a5-4011-9441-d0b5e4122711
     foreign => qr<
\A
.+? : # musicbrainz, 7digital
(?:$long_type) :
(?:[^^]+) \^?
(?:[0-9\.]+)?
\z
>xms,

     # short regex example...
     # ARH6W4X1187B99274F
     short => qr<
\A
(?:$short_type)
(?:[0-9A-Z]{16})
\^? (?:[0-9\.]+)?
\z
>xms,

     # long regex example...
     # music://id.echonest.com/RE/ARH6W4X1187B99274F
     # I just pulled this example out of a hat.
     #
     # [bps 5.28.2011]
     long => qr<
\A
music://id\.echonest\.com/
.+?/
(?:$short_type) /
(?:$short_type)
[0-9A-Z]{16}
\^? (?:[0-9\.]+)?
\z
>xms,
    );

# end code from WWW::Echonest

sub _have_valid_api_key {
    my $self = shift;
    if (length($self->api_key) == 17) {
        return 1;
    }
    return 0;
}

sub get_header_item {
    my $self = shift;
    my $attribute = shift;
    
    if (!defined $attribute) {
        $self->attribute_error('no attribute passed into get_header_item');
        return '';
    }
    
    my @lines = split(/\n/,$self->response_headers());

    my $match = '';
    foreach my $line (@lines) {

        if ($line =~ /$attribute/i) {
            my ($front,$back) = split(/:/,$line,2);
            $back =~ s/^\s+//;
            $back =~ s/\s+$//;
            $match = $back;
        }
    }
    return $match;
}

sub rate_limit {
    my $self = shift;
    return $self->get_header_item('X-Ratelimit-Limit');
}

#

#set_request_paramter - this allow for changing/adding request variables

#

sub set_request_parameter {
    # this is a convience method that allows manipulating the
    # paramters that can be passed as well as setting them to
    # requried if you want to force it for every call
    my $self = shift;
    my $request = shift;
    my $attribute = shift || return "Z";
    
    if (ref($attribute ne 'ARRAY')) {
        return "Y";
    }
    
    if (defined $call_type_attributes{$request}) {
        # print "it already exists\n";
        ${$call_type_attributes{$request}}[0] = $attribute;
        return 1;
    } else {
        # this is a new request type
        # we can just set this as the first
        # array ref
        ${$call_type_attributes{$request}}[0] = $attribute;
        # print Dumper(\%call_type_attributes);
        return 1;
    }   
}

sub get_request_parameter {
    my $self = shift;
    my $request = shift;
    my $attribute = shift || return "Z";
    
    if (!defined $call_type_attributes{$request}) {
        $self->last_error('attribute passed to get_request_parameter does not exist');
        return;
        # return "Y";
    }
    my @local_copy = @{$call_type_attributes{$request}};
    
    foreach my $item (@local_copy) {
        #print "g r p test\n";
        #print Dumper($item);
        my $check = $item->[0];
        if ($check eq $attribute) {
            my @out;
            foreach (1..scalar(@{$item})) {
                push @out , $item->[$_];
            }
            # print "In check\n";
            return @out if wantarray;
            return \@out;
        }
    }
    $self->problem("attribute $attribute not found get_request_parameter failed");
    return;
}

sub rate_limit_used {
    my $self = shift;
    return $self->get_header_item('X-Ratelimit-Used');
}

sub rate_limit_remaining {
    my $self = shift;
    return $self->get_header_item('X-Ratelimit-Remaining');
}

sub sanity_check_id {
    my $self = shift;
    my $id_to_check = shift;
    # pyechonest does a much more specific check then we are going to do
    # we are just going to test some very basic assumptions to *hopefully*
    # avoid breaking anything on the next change to allowed ids
    
    # FIX ME
    
    my $is_valid = 1;
    
    if (length($id_to_check) < 3) {
        return 0;
    }
    
    if ($id_to_check =~ /\n/m) {
        return 0;
    }
    
    return $is_valid;
}

sub attribute_error {
    my $self = shift;
    my $message = shift || '';
    if ($self->debug) {
        warn "$message\n";
    } else {
        $self->problem($message);
    }
    return 1;
}

sub get {
    
    # This seemed like a simple enough method
    # but everything I tried resulted in unacceptable
    # trade offs and explict defining of the structures
    # The new method, which I hope I remember when I
    # revisit it, was to use JSON::Path
    # It is an awesome module, but a little heavy
    # on dependencies.  However I would not have been
    # able to do this in so few lines without it
    
    # Making a generalization here
    # if you use a * you are looking for an array
    # if you don't have an * you want the first 1 (or should I say you get the first 1)

    # here are some examples
    
    #    my ($url,$attribution) = $artist->get(
    #                                           'images[*].url' ,
    #                                           'images[*].license.attribution'
    #                                            
    #                                        );
    
    #    my ($url,$attribution) = $artist->get(
    #                                           'images[0].url' ,
    #                                           'images[0].license.attribution'
    #                                            
    #                                        );
    
    #    my ($url,$attribution) = $artist->get(
    #                                           'images[-1:].url' ,
    #                                           'images[-1:].license.attribution'
    #                                            
    #                                        );
   
    my ($self,@return) = @_;
    # my @return = @_;

    my @out;
    
    my $result = decode_json $self->last_result(); 
    
    my $search_ref = $result->{response};
    
    warn Dumper($result) if $self->debug();
    
    foreach my $key (@return) {
        my $type = 'value';
        if ($key =~ /\*\]/) {
            $type = 'values';
        }
        
        my $jpath = JSON::Path->new("\$.response.$key");
        
        my @t_arr = $jpath->$type($result);
        
        if ($type eq 'value') {
            push @out , $t_arr[0];
        } else {
            push @out , \@t_arr;
        }
    }
    if (wantarray) {
        return @out;    
    } else {
        return $out[0];
    }
    

}


sub seed_count_met {
    my $self = shift;
    my $seed_hashref = shift;
    
    my $count = 0;
    
    foreach my $key (keys %{$seed_hashref}) {
        next if $key eq 'mood';
        next if $key eq 'style';
        $count += $seed_hashref->{$key};    
    }
    
    return 1 if $count >= $self->seed_limit;
    return 0;
}

sub part_of_seed_limit {
    my $self = shift;
    my $item = shift;
    
    my %seed_item = (
      artist => 1,
      artist_id => 1,
      song_id => 1,
      track_id => 1,
      session_catalog => 1
    );
    
    # trying to define attributes considered "seeds" and then
    # appropriately restricting on them
    # this might have a negative effect since it hides
    # some of the API from the user and could change
    # in the future
    # may want to remove this entirely
    if (exists $seed_item{$item}) {
        return 1;
    }
    return 0;
    
}

sub send_get_request {
    # need to build the URL here
    my $self = shift;
    
    my $attributes = shift;
    
    # ensure we have a semi valid api key stashed away
    if ($self->_have_valid_api_key() == 0) {
        return "won't send requests without a valid api key";
    }
    
    if (exists $attributes->{format} && $attributes->{format} =~ /json|xml|xspf|jsonp/) {
        $self->result_format($attributes->{format});
        delete $attributes->{format};
    }
    
    # || ( exists $attributes->{format} && $attributes->{format} eq 'jsonp')
    
    if ( $self->result_format eq 'jsonp' ) {
        return "Need a valid callback with format jsonp" if !$attributes->{callback};
    }
    
    # we can only send 5 (currently) restricts (aka seeds) across ALL
    # multipe parameter types
    # artist, song_id , etc
    
    my $seed_limit = $self->seed_limit();
    
    my %seed_count = ();
    
    my $call_type = $self->call_type();
    
    my $url = $self->build_url_base($call_type);
    
    # since it is a GET we can ? it
    $url .= "?";
    
    # add the api key since it should always be sent
    $url .= "api_key=" . $self->api_key();
    
    # add the format
    
    $url .= "&format=" . $self->result_format();
    
    warn "'$call_type'\n" if $self->debug();
    
    # now depending on the call_type we look for attributes that *might* be passed and are *legal*
    my @from_attributes;
    foreach my $param ( @{ $call_type_attributes{$call_type} } ) {
        
        # set the third [2] element to 0 if it doesn't exist, this indicates
        # if we need to support multiple of these times (array_ref)
        
        if (scalar(@{$param}) == 2) {
            $param->[2] = 0;
        }
        
        
        if ($param->[0] =~ /(.*)\|(.*)/) {
            # this is an either or so we need to see if
            # one of the other exists
            my $t_param;
            if ( exists $attributes->{$1} ) {
                $t_param = $1;
            } 

            if ( exists $attributes->{$2} ) {
                $t_param = $2;
            } 

            if (!$t_param) {
                $self->attribute_error("Neither of these values were passed: $1 $2 , at least one must be present for " . $self->call_type() );
            }
            
            if ($t_param eq 'id') {
                $self->sanity_check_id($attributes->{$t_param});
            }
            
            # print "OK - $t_param\n";
            
            if (ref($attributes->{$t_param}) eq 'ARRAY') {            
                foreach my $item (@{$attributes->{$t_param}}) {
                    push @from_attributes , "$t_param=" . $item; 
                }                    
            } elsif (exists $attributes->{$t_param}) {
                if ($t_param eq 'id') {
                    if (
                        # $self->sanity_check_id($attributes->{$t_param})
                        $self->is_valid_id($attributes->{$t_param})
                        ) {
                        push @from_attributes , "$t_param=" . uri_escape($attributes->{$t_param});
                    }
                } else {
                    push @from_attributes , "$t_param=" . uri_escape($attributes->{$t_param});
                }
            }
            

            
        } elsif (exists $attributes->{ $param->[0] }
                 && ref($attributes->{ $param->[0] }) eq 'ARRAY'
                 && $param->[2] == 1  ) {

            # buckets are special because they can appear twice in a url
            # we will manage this via an arrayref to keep it perly and avoid
            # people thinking they can send to keys with the same name
            
            my $has_limit = $self->part_of_seed_limit($param->[0]);
            
            my $multi_type = $param->[0];
            
            if (!$self->seed_count_met(\%seed_count)) {            
            
                foreach my $item (@{$attributes->{$multi_type}}) {
                    push @from_attributes , "$multi_type=" . $item;
                    $seed_count{$multi_type}++;
                    last if $has_limit && $self->seed_count_met(\%seed_count);
                }
                
            }
        } else {
            if ($attributes->{$param->[0]}) {
                my $has_limit = $self->part_of_seed_limit($param->[0]);
                # look for the possibilty that we feed too many
                # to a seed
                if ( $has_limit && $param->[2] == 1 && $self->seed_count_met(\%seed_count) ) {
                    warn "Seed limit met, skipping $param->[0]\n" if $self->debug;
                    
                } else {
                
                    warn "OK (normal) - $param->[1]\n" if $self->debug();
                    push @from_attributes , "$param->[0]=" . uri_escape_utf8($attributes->{$param->[0]});
                    if ($has_limit && $param->[2] == 1) {
                        # attempting to leverage the data structure that
                        # describes this attribute to enforce limits
                        # FIX ME ?
                        $seed_count{$param->[0]}++;
                    }
                    
                    
                }
            }
        }
    }
    
    my $param_string = join('&',@from_attributes);
    if ($param_string) {
        $url .= '&' . $param_string;
    }
    
    warn "$url\n" if $self->debug;
    
    my $mech = WWW::Mechanize->new( autocheck => 0 );
    $mech->get( $url );
    
    #my $hd;
    #capture { $mech->dump_headers(); } \$hd;

    #$self->response_headers($hd);
    $self->_set_response_headers($mech);
    return $self->format_results($mech->content);
    
}

sub is_valid_json {
    my ($self,$json,$caller) = @_;
    eval {
        decode_json $json;    
    };
    
    if ($@) {
        $self->last_error("invalid josn passed into $caller");
        return 0;
    } else {
        return 1;
    }
}


sub send_post_request {
    my $self = shift;
    my $uri_part = shift;
    my $extra    = shift;
 
    # ensure we have a semi valid api key stashed away
    if ($self->_have_valid_api_key() == 0) {
        my $err_mes = "won't send requests without a valid api key";
        $self->last_error($err_mes);
        return $err_mes;
    }
    
    if (exists $extra->{format} && $extra->{format} =~ /json|xml|xspf|jsonp/) {
        $self->result_format($extra->{format});
        # delete $extra{format};
    }
    
    my $result_format = $self->result_format() || '';
    
    # || ( exists $extra->{format} && $extra->{format} eq 'jsonp' )
    
    if ( $result_format eq 'jsonp' && ! exists $extra->{callback} ) {
        my $err_mes = "Need a valid callback with format jsonp";
        $self->last_error($err_mes);
        return $err_mes;
    }
    
    # if we have "data" in the form elements we need to check its formatting
    # if don't we get a 500 and WWW::Mechanize doesn't like that
    
    if (exists $extra->{data}) {
        if ($self->is_valid_json($extra->{data},"$uri_part") == 0) {
            $self->last_error("invalid json passed into $uri_part");
            return;            
        }
    }
    
    $self->call_type($uri_part);
    
    $extra->{api_key} = $self->api_key();
    
    # if we are going a track/upload we have to manage this slightly differently
    # the $extra data has been seeded with some additional information
    
    my $url = $self->build_url_base();
    
    if ($url !~ /^http/) {
        return "Unable to make uri, got this '$url' instead\n";
    }
    
    warn $url , "\n" if $self->debug();
    
    my $mech;
    my $file;
    
    # needed to ignore SSL host verification
    $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;
    
    if ($self->call_type($uri_part) =~ /upload/ ) {
       
        $mech = WWW::Mechanize->new( );
        # $mech->add_header( $headers->[0] => $headers->[1] );
        $url .= "?api_key=" . $self->api_key();
        $url .= "&filetype=" . $extra->{filetype};
        
        # $mech->filename($extra->{url} || $extra->{track});
        # delete $extra->{filetype};
        
        my $file_contents;
        
        if ($extra->{url} =~ /^(http|ftp)/) {
            my $mech_download = WWW::Mechanize->new();
            $mech_download->get($extra->{url});
            $file_contents = $mech_download->content;
        } else {
        
            open( my $fh , "<" , "$extra->{url}" ) || die "Can't open $extra->{url}: $!";
        
            binmode $fh;
            
            while ( my $chunk = <$fh> ) {
                $file_contents .= $chunk;
            }
        }

        $mech->post( $url ,
                    'Content-Type' => 'application/octet-stream',
                    'Content' => $file_contents
                    );
        
    } else {
        $mech = WWW::Mechanize->new( autocheck => 0 );
        $mech->post( $url , [ $extra ] );
    }
    
    
    $self->_set_response_headers($mech);
    $self->last_error('');
    return $self->format_results($mech->content);

}

sub _set_response_headers {
    my $self = shift;
    my $mech = shift;
    
    my $hd;
    capture { $mech->dump_headers(); } \$hd;

    $self->response_headers($hd);
    return;
}

sub build_url_base {
    # first the uri type
    my $self = shift;
    my $call_type = shift || $self->call_type();
    
  
    my $url = $self->uri_scheme();
    
    # the ://
    $url .= "://";
    
    # the domain
    $url .= $self->uri_hostname();
    
    # the path
    if ( $self->uri_domain_path() ) {
        $url .= "/" . $self->uri_domain_path();
    }
 
    # the version
    if ( $self->uri_domain_path() ) {
        $url .= "/" . $self->version();
    }

        # the path
    if ( $call_type ) {
        $url .= "/" . $call_type;
    }
    return $url;
}

sub request_with_minimum {
    my $self     = shift;
    my $uri_part = shift;
    my $extra    = shift;
    
    if (defined $call_type_attributes{$uri_part}) {
        if (scalar keys %{$extra} == 0) {
            $self->attribute_error("'$uri_part' requires at least 1 parameter to be passed");
        } else {
            $self->call_type($uri_part);
            return $self->send_get_request($extra);
        }
    } else {
        $self->attribute_error("invalid API call, either it is a typo or this feature doens't exist yet ($uri_part)");
    }
    return "error";
}

sub request_with_no_minimum {
    my $self     = shift;
    my $uri_part = shift;
    my $extra    = shift;
    
    if (defined $call_type_attributes{$uri_part}) {    
        $self->call_type($uri_part);
        return $self->send_get_request($extra);
    } else {
        $self->attribute_error("invalid API call, either it is a typo or this feature doesn't exist yet ($uri_part)");
    }
    return "error";
}

sub get_status_code {
    my ($self,$num_only) = @_;

    my ($code) = $self->get( 'status.code' );
    if ($num_only) {
        return $code;
    }
    
    return $code_to_name{$code};
}

sub is_valid_id {
    # FIX ME
    # need to make the id that was passed is of a valid format
    # typically just need to make with it has a sane struture
    # if and how do other libraries do this?
    
    # borrowed code from the WWW::EchoNest Perl lib
    # see comments in that data structure else where
    # in this file
    
    my ($self,$identifier) = @_;
    # my ($identifier) = @_;

    return if ! defined($identifier);
    
    for my $id_regex (values %id_regex_for) {
        return 1 if $identifier =~ /$id_regex/;
    }
    
    return;
    
    
}

sub get_file_extension {
    my ($self,$uri) = @_;
    if (!$uri) {
        return "no uri passed into get_filetype";
    }
    
    my $basename;
    
    if ($uri =~ /^(http|ftp)/) {
        my $uri_obj = URI->new($uri);
        $basename = ( $uri_obj->path_segments )[-1];
    } else {
        $basename = $uri;
    }
    
    my @extensions = qw( wav mp3 au ogg m4a mp4 );
    
    my ($dir,$name,$ext) = fileparse($basename);
    
    if ($basename && $ext) {
        return $ext;
    }
    return;
}

sub format_results {
    my $self = shift;
    my $content = shift;
    
    # want to store the result in case
    # we want to interact with it via a helper method
    $self->last_result($content);
    
    # FIX ME / TEST ME
    # vefify both of these work and return the *same* perl hash
    
    # when / how should we check the status? Do we need to?
    # if so then we need to create another method that will
    # manage a Sucess vs. Fail request
    
    if ($self->auto_json_decode && $self->result_format eq 'json' ) {
        return decode_json $content;
    }

    if ($self->auto_xml_decode && $self->result_format eq 'xml' ) {
        # FIX ME
        my $xs = XML::Simple->new();
        return $xs->XMLin($content);
    }
    
    # results are not altered in this cass and would be either
    # json or xml instead of a perl data structure
    
    return $content;
}

sub get_resource_md5 {
    
    my ($self,$resource) = @_;
    
    my $md5;
     
    if ($resource =~ /^http|ftp/) {
        # getting data from online
        # lets see if we can avoid the actaul analysis and get an md5
        $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;
        $md5 = url_md5_hex($resource);   
    } else  {
        # using a local audio file
        # do we need to upload it? see if there is already an md5 available for it
        # warn "ends with approriate file extension\n";
        $md5 = file_md5_hex($resource);
    }
    
    return $md5;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 NAME

WWW::TheEchoNest - Wrapper for The Echo Nest API of music intelligence

=head1 VERSION

version 1.1

=head1 SYNOPSIS

See the specific types of calls for details. All types (Artist,Song,etc) inherit
from this module and you could call them via those objects.

L<WWW::TheEchoNest::Artist>
L<WWW::TheEchoNest::Codegen>
L<WWW::TheEchoNest::Playlist>
L<WWW::TheEchoNest::Song>
L<WWW::TheEchoNest::TasteProfile>
L<WWW::TheEchoNest::Track>

=head1 DESCRIPTION

WWW::TheEchoNest provides a robust wrapper around The Echo Nest API to provide
access to nearly all the current features and provide some flexibility should
features change without having to rely on an update to this module.

You B<must> read The Echo Nest documentation. This module attempts to provide as
much coverage as possible for their API and the structure resembles the calls
url as closely as possible.  One excpetion to this is the tasteprofile/dynamic calls
that have an additional URL part (dynamic/create, etc), these are represented
as dynamic_create, dynamic_next, etc.

http://developer.echonest.com/docs/v4

Have access to a JSON viewer to help develop and debug. The Chrome JSON viewer is
very good and provides the exact path of the item within the JSON in the lower left
of the screen as you mouse over an element.

=head1 NAME

WWW::TheEchoNest

=head1 REQUIRES

Moose 

L<IO::CaptureOutput> 

L<Scalar::Util> 

L<HTTP::Headers> 

L<XML::Simple> 

L<JSON::Path> 

L<JSON::XS> 

L<WWW::Mechanize> 

L<URI::Escape> 

L<Digest::MD5::File>

=head1 INHERITED METHODS

You may see these mentioned in the examples in the Artist, Song, etc.

=head2 debug

When this is set to 1 debugging statements will be displayed.

 $artist->debug(1);

One item that will be displayed is the URL that was constructed. This can help
you track down cases where your parameters were dropped.

=head2 get

Returns a specific item or array of items from the JSON result of the
last action.

 $song->search( title => 'Stairway to Heaven',
                artist => 'Led Zeppelin'
                );
 
 my $track_id = $song->get( 'songs[0].tracks[0].id' );

JSON::Path is the underlying library that actually parses the JSON.

This can also be called in an array context so you can get all of the items.

 $playlist->basic(
                            artist => 'Weezer',
                            type => 'artist-radio'
                            );
 
  my @songs = $catalog->get( 'songs[*]' );

=head2 get_status_code

 my $status_code_as_string = $artist->get_status_code();

or

 my $status_code_as_number = $artist->get_status_code(1);

Refer to The Echo Nest documentation for information on possible
response codes.

=head2 rate_limit

The Echo Nest restricts calls to their API via a rate limit. To acces your
current rate limit use the rate_limit method. It will return a numerical value
that represents the number of requests per minute you are allowed to make.

 $artist->rate_limit();

=head2 rate_limit_remaining

Will return the number of calls remaining in your rate limit

 $artist->rate_limit_remaining();

=head2 rate_limit_used

Will return the number of calls you have made to the rate limit

 $artist->rate_limit_used();

=head2 get_header_item

Will return any item you specify from the http header. You generally only
need to use the rate_ calls, but if something changes in the API response
this method would allow you to access it.

 $artist->get_header_item('X-Rate-Limit');

=head2 get_request_parameter

There is an attempt to enforce that required items are passed for each call
this method can help you determine what the current setting is for a particular
call.

 my @grp = $song->get_request_parameter( 'song/search' , 'limit' );

It returns an array of the contents, will be 1 or 2 elements, the first is if the
item is required and the second is if it has a limit of how many of them
can be passed per request.

In order to allow you to create your own restrictions or add items that become
available after this module was created you can use the set_ method below

=head2 set_request_parameter

Allows you to add a new request parameter or enforce a restriction. For example
you might want to enfore an artist_id is always passed into song/search

 $artist->set_request_parameter( 'song/search' , [ 'artist_id' , 1  ] );

or to add a new item

 $artist->set_request_parameter( 'song/newfeature' , [ 'limit' , 1  ] );

This same process is what disallows/prevents parameters that aren't already in the
list from being sent.  See debug below for more info.

=head2 auto_json_decode

When this is set all calls will return a perl data structure rather than the JSON

 $artist->auto_json_decode(1);

NOTE: You can still access the JSON via the last_result() method

=head2 auto_xml_decode

When this is set all calls will return a perl data structure rather than XML

You must also set the result_format to 'xml' for this to work

 $artist->auto_xml_decode(1);

NOTE: You can still access the XML via the last_result() method

=head2 last_result

Will give you the actual output from the call to the API. The format will match the result_format
you specified for the request. The default output is JSON.

 print $artist->last_result();

=head2 last_error

Will provide information on possible errors encounterd on your method call. This is a plain
text string with content like:

"invalid json passed into tasteprofile/update"

 print $artist->last_error();

=head1 INTERNAL METHODS

These typically never need to be used directly, but are provided here in case
you feel the need to look under the hood.

These are not documented as of the .02 release since they aren't normally needed
possibly in future releases these will be documented more.

=head2 attribute_error

Provides access to attribute errors that are set when a call fails due to missing
parameters or mispellings

 $obj->attribute_error();

=head2 build_url_base

Can provide you with a base url if feed the proper paramters.

 $obj->build_url_base();

=head2 format_results

 $obj->format_results();

=head2 is_valid_id

 $obj->is_valid_id();

=head2 part_of_seed_limit

 $obj->part_of_seed_limit();

=head2 request_with_minimum

 $obj->request_with_minimum();

=head2 request_with_no_minimum

 $obj->request_with_no_minimum();

=head2 sanity_check_id

 $obj->sanity_check_id();

=head2 seed_count_met

 $obj->seed_count_met();

=head2 send_get_request

 $obj->send_get_request();

=head2 send_post_request

 $obj->send_post_request();

=head2 get_file_extension

 $obj->get_file_extension();

=head2 get_resource_md5

 $obj->get_resource_md5();

=head2 is_valid_json

 $obj->is_valid_json();

=head1 THANKS

Brian Sorahan is the authoer of L<WWW::EchoNest> and some ideas and a couple
chunks of code served as a guideline. It has many convience methods that
may make it a better choice for some use cases.

=head1 AUTHOR

Aaron Johnson <aaronjjohnson@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Aaron Johnson.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
