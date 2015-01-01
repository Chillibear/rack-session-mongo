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
puts "_*___init"        
        # Allow a session to be directly passed in
        options = { moped_session: options } if options.is_a? ::Moped::Session
puts "_*___options = #{options.inspect}"
        # Merge user passed parameters with the defaults from this and the Rack session
        @options = DEFAULT_OPTIONS.merge options         
puts "_*___merged options = #{options.inspect}"
        super        

        # Tidy up passed in mongo hosts
        hosts = []
        (hosts << options[:mongo_host] << options[:mongo_hosts]).flatten.uniq.compact
        hosts << DEFAULT_MONGO_HOST if hosts.empty?
                
        # Setup or re-use DB session
        moped_session = nil
        if options.has_key? :moped_session
puts "_*___moped session passed in"
          if options[:moped_session].is_a? ::Moped::Session            
puts "_*___using moped session"
            moped_session = options[:moped_session] 
          else
puts "_*___using hosts because session object is not a session"            
            moped_session = ::Moped::Session.new( hosts )
          end
        else
puts "_*___using hosts because no session passed in"            
          moped_session = ::Moped::Session.new( hosts )          
        end 
puts "_*___using DB: #{@options[:mongo_db_name].to_s}"
        moped_session.use( @options[:mongo_db_name].to_s ) 

puts "_*___creating session pool object"
puts "_*___using collection #{@options[:mongo_collection].to_s }"        
        @sessions = moped_session[ @options[:mongo_collection].to_s ] 
puts "_*___creating index"        
        @sessions.indexes.create(
          { sid: 1 },
          { unique: true }
        )
puts "_*___creating mutex"        
        @mutex = Mutex.new
      end

      # ------------------------------------------------------------------------
      def generate_sid
puts "_*___[generate_sid]"
        loop do
          sid = super
puts "_*___[generate_sid] looping during generation of sid"          
puts "_*___[generate_sid] generated sid is #{sid}."    
puts "_*___[generate_sid] does session exits? #{@sessions.find(sid: sid).count > 0 ? 'yes' : 'no'}."          
          break sid unless (@sessions.find(sid: sid).count > 0)
        end
      end

      # ------------------------------------------------------------------------
      def get_session(env, sid)
        with_lock(env, [nil, {}]) do       
puts "_*___[get_session] performing find"          
          session = @sessions.find(sid: sid)
puts "_*___[get_session] E find returned #{session.count} results"                    
          if session.count > 0
puts "_*___[get_session] E using existing found session" 
            session_data = _unpack( doc['data'] )
puts "_*___[get_session] E unpacked data: #{session_data}"
            return [sid, session_data]
          else
puts "_*___[get_session] N no existing session found, generating new one"            
            sid = generate_sid
puts "_*___[get_session] N new sid = #{sid}"           
            return [sid, {}]
          end
        end
      end

      # ------------------------------------------------------------------------
      def set_session(env, session_id, new_session, options)
        with_lock(env, false) do
puts "_*___[set_session] setting data in session"
puts "_*___[set_session] generating new session id because supplied one is nil" if session_id.nil?
          session_id = generate_sid if session_id.nil?
puts "_*___[set_session] setting session '#{session_id}' data to '#{new_session}'."
          session = @sessions.find(sid: session_id)
          if session.count > 0
puts "_*___[set_session] found existing session so updating data"
            session.update('$set' => { data: _pack(new_session), updated_at: Time.now.utc })
          else
puts "_*___[set_session] creating new session using #{session_id}"            
            @sessions.insert( sid: session_id, data: _pack(new_session), updated_at: Time.now.utc )
          end
puts "_*___[set_session] returning session id #{session_id}"          
          return session_id
        end
      end

      # ------------------------------------------------------------------------
      def destroy_session(env, session_id, options)
        with_lock(env) do
puts "_*___[destroy_session] destroy session  '#{session_id}'."          
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
puts "_*___[_pack] #{data}"        
        return nil unless data        
        @options[:marshal_data] ? [ Marshal.dump(data) ].pack('m') : data
      end

      # ------------------------------------------------------------------------
      def _unpack(packed)
puts "_*___[_unpack] #{packed}"        
        return nil unless packed
        @options[:marshal_data] ? Marshal.load( packed.unpack('m').first ) : packed
      end
    end
  end
end
