require 'rack/session/abstract/id'
require 'moped'

module Rack
  module Session
    class Moped < Abstract::ID

      attr_reader :mutex, :pool

      DEFAULT_OPTIONS = Abstract::ID::DEFAULT_OPTIONS.merge({
        mongo_db_name:    :racksessions, 
        mongo_collection: :sessions, 
        marshal_data:     true
      })
      DEFAULT_MONGO_HOST = 'localhost:27017'

      # ------------------------------------------------------------------------
      def initialize(app, options={})
puts "____init"        
        # Allow a session to be directly passed in
        options = { moped_session: options } if options.is_a? ::Moped::Session
puts "____options = #{options.inspect}"
        # Merge user passed parameters with the defaults from this and the Rack session
        @options = DEFAULT_OPTIONS.merge options         
puts "____merged options = #{options.inspect}"
        super        

        # Tidy up passed in mongo hosts
        hosts = []
        (hosts << options[:mongo_host] << options[:mongo_hosts]).flatten.uniq.compact
        hosts << DEFAULT_MONGO_HOST if hosts.empty?
                
        # Setup or re-use DB session
        moped_session = nil
        if options.has_key? :moped_session
puts "____moped session passed in"
          if options[:moped_session].is_a? ::Moped::Session            
puts "____using moped session"
            moped_session = options[:moped_session] 
          else
puts "____using hosts because session object is not a session"            
            moped_session = ::Moped::Session.new( hosts )
          end
        else
puts "____using hosts because no session passed in"            
          moped_session = ::Moped::Session.new( hosts )          
        end 
puts "____using DB: #{@options[:mongo_db_name].to_s}"
        moped_session.use( @options[:mongo_db_name].to_s ) 

puts "____creating session pool object"
puts "____using collection #{@options[:mongo_collection].to_s }"        
        @sessions = moped_session[ @options[:mongo_collection].to_s ] 
puts "____creating index"        
        @sessions.indexes.create(
          { sid: 1 },
          { unique: true }
        )
puts "____creating mutex"        
        @mutex = Mutex.new
      end

      # ------------------------------------------------------------------------
      def generate_sid
puts "____[generate_sid] generating sid"
        loop do
puts "____[generate_sid] looping during generation of sid"
          sid = super
puts "____[generate_sid] generated sid is #{sid}."          
          break sid unless (@sessions.find.count(sid: sid) > 0)
        end
puts "____[generate_sid] generated sid of #{sid}"        
      end

      # ------------------------------------------------------------------------
      def get_session(env, sid)
puts "____[get_session] getting session #{sid}"         
        with_lock(env, [nil, {}]) do
puts "____[get_session] with lock and env #{env}"          
          unless sid and (session = _get(sid))
puts "____[get_session] fetched session #{session}"            
            sid, session = generate_sid, {}
puts "____[get_session] saving new session #{sid} / #{session}"            
            _put sid, session
          end
          [sid, session]
        end
      end

      # ------------------------------------------------------------------------
      def set_session(env, session_id, new_session, options)
        with_lock(env, false) do
          _put session_id, new_session
          session_id
        end
      end

      # ------------------------------------------------------------------------
      def destroy_session(env, session_id, options)
        with_lock(env) do
          _delete(session_id)
          generate_sid unless options[:drop]
        end
      end

      # ------------------------------------------------------------------------
      def with_lock(env, default=nil)
        @mutex.lock if env['rack.multithread']
        yield
      rescue
        default
      ensure
        @mutex.unlock if @mutex.locked?
      end

    # ==========================================================================
    private
      # ------------------------------------------------------------------------
      def _put(sid, session)
puts "____[_put] #{sid}"        
        @sessions.find(sid: sid).upsert(sid: sid, data: _pack(session), updated_at: Time.now.utc)
      end    

      # ------------------------------------------------------------------------
      def _get(sid)
puts "____[_get] #{sid}"  
        doc = @sessions.find.one(sid: sid)
        if doc = @sessions.find.one(sid: sid)
puts "____[_get] session exists #{sid}"          
          _unpack( doc['data'] )
        end
      end

      # ------------------------------------------------------------------------
      def _delete(sid)
puts "____[_delete] #{sid}"        
        @sessions.remove(sid: sid)
      end

      # ------------------------------------------------------------------------
      def _pack(data)
puts "____[_pack] #{data}"        
        return nil unless data        
        @options[:marshal_data] ? [ Marshal.dump(data) ].pack('m') : data
      end

      # ------------------------------------------------------------------------
      def _unpack(packed)
puts "____[_unpack] #{packed}"        
        return nil unless packed
        @options[:marshal_data] ? Marshal.load( packed.unpack('m').first ) : packed
      end
    end
  end
end
