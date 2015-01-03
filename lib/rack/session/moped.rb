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
        # Allow a session to be directly passed in
        options = { moped_session: options } if options.is_a? ::Moped::Session
        # Merge user passed parameters with the defaults from this and the Rack session
        @options = DEFAULT_OPTIONS.merge options         
        super        

        # Tidy up passed in mongo hosts
        hosts = []
        (hosts << options[:mongo_host] << options[:mongo_hosts]).flatten.uniq.compact
        hosts << DEFAULT_MONGO_HOST if hosts.empty?
                
        # Setup or re-use DB session
        moped_session = nil
        if options.has_key? :moped_session
          if options[:moped_session].is_a? ::Moped::Session            
            moped_session = options[:moped_session] 
          else
            moped_session = ::Moped::Session.new( hosts )
          end
        else
          moped_session = ::Moped::Session.new( hosts )          
        end 
        moped_session.use( @options[:mongo_db_name].to_s ) 

        @sessions = moped_session[ @options[:mongo_collection].to_s ] 
        @sessions.indexes.create(
          { sid: 1 },
          { unique: true }
        )       
        @mutex = Mutex.new
      end

      # ------------------------------------------------------------------------
      def generate_sid
        loop do
i = Random.rand(100)          
puts "_^__#{i}_[generate_sid]"
          sid = super
puts "_^__#{i}_[generate_sid] looping during generation of sid"          
puts "_^__#{i}_[generate_sid] generated sid is #{sid}."    
puts "_^__#{i}_[generate_sid] does session exits? #{@sessions.find(sid: sid).count > 0 ? 'yes' : 'no'}."          
          break sid unless (@sessions.find(sid: sid).count > 0)
        end
      end

      # ------------------------------------------------------------------------
      def get_session(env, sid)
        session_data = {}
        with_lock(env, [nil, {}]) do  
puts "____#{env['REQUEST_URI']}"           
i = Random.rand(100)               
puts "_^__#{i}_[get_session] performing find on '#{sid}'"          
          found_sessions = @sessions.find(sid: sid)
puts "_^__#{i}_[get_session] E find returned #{session.count} results"                    
          if found_sessions.count > 0
puts "_^__#{i}_[get_session] E using existing found session ..."
puts "_^__#{i}_[get_session] E about to unpack the data (#{found_sessions.first['data']})"
puts "_^__#{i}_[get_session] E are we unpacking? #{@options[:marshal_data]}"
            session_data = _unpack( found_sessions.first['data'] )
puts "_^__#{i}_[get_session] E unpacked data: #{session_data}"            
          else
puts "_^__#{i}_[get_session] N no existing session found, generating new one"            
            sid = generate_sid
puts "_^__#{i}_[get_session] N new sid = #{sid}"                     
          end
        end
        return [sid, session_data]
      end

      # ------------------------------------------------------------------------
      def set_session(env, session_id, new_session, options)
        with_lock(env, false) do
i = Random.rand(100) 
puts "_^__#{i}_[set_session] setting data in session"
puts "_^__#{i}_[set_session] generating new session id because supplied one is nil" if session_id.nil?
          session_id = generate_sid if session_id.nil?
puts "_^__#{i}_[set_session] setting session '#{session_id}' data to '#{new_session}'."
          found_sessions = @sessions.find(sid: session_id)
          if found_sessions.count > 0
puts "_^__#{i}_[set_session] found existing session so updating data"
            found_sessions.first.update('$set' => { data: _pack(new_session), updated_at: Time.now.utc })
          else
puts "_^__#{i}_[set_session] creating new session using #{session_id}"            
            @sessions.insert( sid: session_id, data: _pack(new_session), updated_at: Time.now.utc )
          end
puts "_^__#{i}_[set_session] returning session id #{session_id}"          
        end
        return session_id
      end

      # ------------------------------------------------------------------------
      def destroy_session(env, session_id, options)
        with_lock(env) do
          @sessions.remove(sid: sid)
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
      def _pack(data)
puts "_^___[_pack] #{data}"        
        return nil unless data        
        @options[:marshal_data] ? [ Marshal.dump(data) ].pack('m') : data
      end

      # ------------------------------------------------------------------------
      def _unpack(packed)
puts "_^___[_unpack] #{packed}"        
        return nil unless packed
        @options[:marshal_data] ? Marshal.load( packed.unpack('m').first ) : packed
      end
    end
  end
end
