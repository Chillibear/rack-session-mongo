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

        @pool = moped_session[ @options[:mongo_collection].to_s ] 
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
          break sid unless (@sessions.find(sid: sid).count > 0)
        end
      end

      # ------------------------------------------------------------------------
      def get_session(env, sid)
        session_data = {}
        begin
          @mutex.lock if env['rack.multithread']             

          session = _find(sid) if sid
          unless sid and session
            session = {}
            sid = generate_sid
            _save(sid)
          end
          session.instance_variable_set('@old', {}.merge(session))
          session.instance_variable_set('@sid', sid)
          return [sid, session]

        ensure
          @mutex.unlock if @mutex.locked?
        end        
      end

      # ------------------------------------------------------------------------
      def set_session(env, session_id, new_session, options)
        begin
          @mutex.lock if env['rack.multithread']
          session = _find || {}
          
          if options[:renew] or options[:drop]
            @pool.remove(sid: session_id)
            return false if options[:drop]
            session_id = generate_sid
            @pool.insert( sid: session_id, data: _pack({}), updated_at: Time.now.utc )
          end
          
          old_session = new_session.instance_variable_get('@old') || {}
          session = merge_sessions( session_id, old_session, new_session, session )
          
          @pool.save session_id, session
          return session_id
        ensure
          @mutex.unlock if env['rack.multithread']
        end
      end  
      
  
      # ------------------------------------------------------------------------
      def destroy_session(env, session_id, options)
        begin
          @mutex.lock if env['rack.multithread']
          @sessions.remove(sid: sid)
          options[:drop] ? nil : generate_sid 
        ensure
          @mutex.unlock if @mutex.locked?
        end
      end


    # ==========================================================================
    private
    
      # ------------------------------------------------------------------------
      def merge_sessions(sid, old_session, new_session, current_session=nil)
        current_session ||= {}
        return current_session unless Hash === old_session and Hash === new_session

        # delete keys that are not in common
        #delete = current.keys - (new_session.keys & current.keys)
        delete = old_session.keys - new_session.keys
        delete.each{|k| current_session.delete k }

        #update = new_session.keys.select{|k| !current.has_key?(k) || new_session[k] != current[k] || new_session[k].kind_of?(Hash) || new_session[k].kind_of?(Array) }    
        update = new_session.keys.select{|k| new_session[k] != old_session[k] }
        update.each{|k| current_session[k] = new_session[k] }

        current_session
      end    
    
      # ------------------------------------------------------------------------
      def _find(sid)
        session = @pool.find(sid: sid).first # nil if nothing is found
        session.nil? ? false : _unpack( session['data'] )
      end    
    
      # ------------------------------------------------------------------------
      def _save(sid, session={})
        @pool.find(sid: sid).upsert("$set" => { data: _pack(session), updated_at: Time.now.utc })
      end    

      # ------------------------------------------------------------------------
      def _pack(data)      
        return nil unless data        
        @options[:marshal_data] ? [ Marshal.dump(data) ].pack('m*') : data
      end

      # ------------------------------------------------------------------------
      def _unpack(packed)       
        return nil unless packed
        @options[:marshal_data] ? Marshal.load( packed.unpack('m*').first ) : packed
      end
    end
  end
end
