rack-session-moped
==================

Rack session store for MongoDB using Moped drive

<https://github.com/Chillibear/rack-session-mongo>

## Installation

    gem install rack-session-moped

## Usage

Simple (localhost:27017 db:sessions, collection:sessions)

    use Rack::Session::Moped

Set MongoDB connection using Moped

    connection = ......
    use Rack::Session::Moped, connection

Specify with some config

    use Rack::Session::Moped, {
      :host         => 'myhost:27017',
      :db_name      => 'myapp',
      :marshal_data => false,
      :expire_after => 600
    }

## Options

The following options can be passed to Rack::Session::Moped 

* `host`  : A Mongo host supplied as a string in the format "host:port"
* `hosts` : One or more Mongo host supplied as an array in the format [ "host:port", "host:port" ]
* `mongo_db_name` : The Mongo database to use (defaults to _sessions_), a string for the name should be supplied
* `mongo_collection` : The Mongo collection to use (defaults to _sessions_), a string for the name should be supplied
* `marshal_data` : A boolean to determine if session data should be marshalled (defaults to _true_) 

All other standard Rack [Abstract::ID::DEFAULT_OPTIONS](http://www.rubydoc.info/github/rack/rack/Rack/Session/Abstract/ID) can be passed in to be overridden.

## About MongoDB and Moped

- <http://www.mongodb.org/>
- <http://mongoid.org/en/moped/>

## License
[rack-session-moped](https://github.com/Chillibear/rack-session-mongo) distributed under the [MIT license](http://www.opensource.org/licenses/mit-license)

[rack-session-mongo](http://github.com/migrs/rack-session-mongo) on which this is based is Copyright (c) 2012 [Masato Igarashi](http://github.com/migrs)(@[migrs](http://twitter.com/migrs)) and distributed under the [MIT license](http://www.opensource.org/licenses/mit-license).
