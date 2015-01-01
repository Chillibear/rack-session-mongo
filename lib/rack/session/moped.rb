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
puts "_-___init"        
        # Allow a session to be directly passed in
        options = { moped_session: options } if options.is_a? ::Moped::Session
puts "_-___options = #{options.inspect}"
        # Merge user passed parameters with the defaults from this and the Rack session
        @options = DEFAULT_OPTIONS.merge options         
puts "_-___merged options = #{options.inspect}"
        super        

        # Tidy up passed in mongo hosts
        hosts = []
        (hosts << options[:mongo_host] << options[:mongo_hosts]).flatten.uniq.compact
        hosts << DEFAULT_MONGO_HOST if hosts.empty?
                
        # Setup or re-use DB session
        moped_session = nil
        if options.has_key? :moped_session
puts "_-___moped session passed in"
          if options[:moped_session].is_a? ::Moped::Session            
puts "_-___using moped session"
            moped_session = options[:moped_session] 
          else
puts "_-___using hosts because session object is not a session"            
            moped_session = ::Moped::Session.new( hosts )
          end
        else
puts "_-___using hosts because no session passed in"            
          moped_session = ::Moped::Session.new( hosts )          
        end 
puts "_-___using DB: #{@options[:mongo_db_name].to_s}"
        moped_session.use( @options[:mongo_db_name].to_s ) 

puts "_-___creating session pool object"
puts "_-___using collection #{@options[:mongo_collection].to_s }"        
        @sessions = moped_session[ @options[:mongo_collection].to_s ] 
puts "_-___creating index"        
        @sessions.indexes.create(
          { sid: 1 },
          { unique: true }
        )
puts "_-___creating mutex"        
        @mutex = Mutex.new
      end

      # ------------------------------------------------------------------------
      def generate_sid
puts "_-___[generate_sid] generating sid"
        loop do
puts "_-___[generate_sid] looping during generation of sid"
          sid = super
puts "_-___[generate_sid] generated sid is #{sid}."    
puts "_-___[generate_sid] session exits? #{@sessions.find(sid: sid).count > 0}."          
          break sid unless (@sessions.find(sid: sid).count > 0)
        end
      end

      # ------------------------------------------------------------------------
      def get_session(env, sid)
puts "_-___[get_session] getting session #{sid}"         
        with_lock(env, [nil, {}]) do
          unless sid and (session = _get(sid))
puts "_-___[get_session] fetched session #{session}"            
            sid, session = generate_sid, {}
puts "_-___[get_session] saving new session #{sid} / #{session}"            
            _put sid, session
          end
          [sid, session]
        end
      end

      # ------------------------------------------------------------------------
      def set_session(env, session_id, new_session, options)
puts "_-___[set_session]"
        session_id = generate_sid if session_id.nil?
        with_lock(env, false) do
puts "_-___[set_session] setting session '#{session_id}' to '#{new_session}'."
          _put session_id, new_session
          session_id
        end
      end

      # ------------------------------------------------------------------------
      def destroy_session(env, session_id, options)
puts "_-___[destroy_session] "
        with_lock(env) do
puts "_-___[destroy_session] destroy session  '#{session_id}'."          
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
puts "_-___[_put] #{sid} / #{session}"
puts "_-___[_put] session exists? (#{@sessions.find(sid: sid).count>0 ? 'yes' : 'no'})"        
        result = @sessions.find(sid: sid).upsert(sid: sid, data: _pack(session), updated_at: Time.now.utc)
puts "_-___[_put] result = #{result}"        
        return result
      end    

      # ------------------------------------------------------------------------
      def _get(sid)
puts "_-___[_get] #{sid}"
        doc = @sessions.find(sid: sid)
puts "_-___[_get] returned doc = #{doc}"         
        if doc.count > 0
puts "_-___[_get] session exists #{sid}, unpacking data"          
          return _unpack( doc['data'] )
        else
puts "_-___[_get] returning nil, because session does not exist"          
          return nil
        end
      end

      # ------------------------------------------------------------------------
      def _delete(sid)
puts "_-___[_delete] #{sid}"        
        @sessions.remove(sid: sid)
      end

      # ------------------------------------------------------------------------
      def _pack(data)
puts "_-___[_pack] #{data}"        
        return nil unless data        
        @options[:marshal_data] ? [ Marshal.dump(data) ].pack('m') : data
      end

      # ------------------------------------------------------------------------
      def _unpack(packed)
puts "_-___[_unpack] #{packed}"        
        return nil unless packed
        @options[:marshal_data] ? Marshal.load( packed.unpack('m').first ) : packed
      end
    end
  end
end
