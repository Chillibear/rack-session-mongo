require 'rack/session/abstract/id'
require 'moped'

module Rack
  module Session
    class Moped < Abstract::ID

      attr_reader :mutex, :pool

      DEFAULT_OPTIONS = Abstract::ID::DEFAULT_OPTIONS.merge({
        mongo_db_name:    :sessions, 
        mongo_collection: :sessions, 
        marshal_data:     true
      })

      # ------------------------------------------------------------------------
      def initialize(app, options={})
        
        # Allow a session to be directly passed in
        options = { moped_session: options } if options.is_a? ::Moped::Session

        # Merge user passed parameters with the defaults from this and the Rack session
        @options = DEFAULT_OPTIONS.merge options         
        super        
                
        # Setup or re-use DB session
        session = nil
        if options.has_key? :moped_session
          if options[:moped_session].is_a? ::Moped::Session
            session = options[:moped_session] 
          else
            hosts = []
            hosts << options[:mongo_host]
            hosts << options[:mongo_hosts]
            hosts.flatten!
            hosts.compact!
            session = Moped::Session.new( hosts )
          end
        end 
        session.use @options[:mongo_db_name].to_s 
        
        @pool = session[ @options[:mongo_collection].to_s ]
        @pool.indexes.create(
          { sid: 1 },
          { unique: true }
        )
        @mutex = Mutex.new
      end

      # ------------------------------------------------------------------------
      def generate_sid
        loop do
          sid = super
          break sid unless _exists? sid
        end
      end

      # ------------------------------------------------------------------------
      def get_session(env, sid)
        with_lock(env, [nil, {}]) do
          unless sid and session = _get(sid)
            sid, session = generate_sid, {}
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
        @pool.update({ sid: sid },
           {"$set" => {:data  => _pack(session), :updated_at => Time.now.utc}}, :upsert => true)
      end

      # ------------------------------------------------------------------------
      def _get(sid)
        if doc = _exists?(sid)
          _unpack(doc['data'])
        end
      end

      # ------------------------------------------------------------------------
      def _delete(sid)
        @pool.remove(sid: sid)
      end

      # ------------------------------------------------------------------------
      def _exists?(sid)
        @pool.find(sid: sid)
      end

      # ------------------------------------------------------------------------
      def _pack(data)
        return nil unless data
        @options[:marshal_data] ? [Marshal.dump(data)].pack("m*") : data
      end

      # ------------------------------------------------------------------------
      def _unpack(packed)
        return nil unless packed
        @options[:marshal_data] ? Marshal.load(packed.unpack("m*").first) : packed
      end
    end
  end
end
