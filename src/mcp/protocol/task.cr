module MCP::Protocol
  enum TaskSupport
    Forbidden
    Optional
    Required
  end

  struct ToolExecution
    include JSON::Serializable

    @[JSON::Field(key: "taskSupport")]
    getter task_support : TaskSupport?

    def initialize(@task_support = nil)
    end
  end

  enum TaskStatus
    Working
    InputRequired
    Completed
    Failed
    Cancelled
  end

  struct Task
    include JSON::Serializable

    @[JSON::Field(key: "taskId")]
    getter task_id : String
    getter status : TaskStatus
    @[JSON::Field(key: "statusMessage")]
    getter status_message : String?
    @[JSON::Field(key: "createdAt")]
    getter created_at : String
    @[JSON::Field(key: "lastUpdatedAt")]
    getter last_updated_at : String
    getter ttl : Int64?
    @[JSON::Field(key: "pollInterval")]
    getter poll_interval : Int64?

    def initialize(@task_id, @status = TaskStatus::Working, @status_message = nil,
                   @created_at = Time.utc.to_s("%FT%TZ"), @last_updated_at = Time.utc.to_s("%FT%TZ"),
                   @ttl = nil, @poll_interval = nil)
    end
  end

  class CreateTaskResult < Result
    getter task : Task

    def initialize(@task, @meta = nil)
      super(@meta)
    end
  end

  class GetTaskResult < Result
    @[JSON::Field(key: "taskId")]
    getter task_id : String
    getter status : TaskStatus
    @[JSON::Field(key: "statusMessage")]
    getter status_message : String?
    @[JSON::Field(key: "createdAt")]
    getter created_at : String
    @[JSON::Field(key: "lastUpdatedAt")]
    getter last_updated_at : String
    getter ttl : Int64?
    @[JSON::Field(key: "pollInterval")]
    getter poll_interval : Int64?

    def initialize(@task_id, @status, @status_message = nil, @created_at = Time.utc.to_s("%FT%TZ"),
                   @last_updated_at = Time.utc.to_s("%FT%TZ"), @ttl = nil, @poll_interval = nil, @meta = nil)
      super(@meta)
    end
  end

  class CancelTaskResult < Result
    @[JSON::Field(key: "taskId")]
    getter task_id : String
    getter status : TaskStatus
    @[JSON::Field(key: "statusMessage")]
    getter status_message : String?
    @[JSON::Field(key: "createdAt")]
    getter created_at : String
    @[JSON::Field(key: "lastUpdatedAt")]
    getter last_updated_at : String
    getter ttl : Int64?
    @[JSON::Field(key: "pollInterval")]
    getter poll_interval : Int64?

    def initialize(@task_id, @status, @status_message = nil, @created_at = Time.utc.to_s("%FT%TZ"),
                   @last_updated_at = Time.utc.to_s("%FT%TZ"), @ttl = nil, @poll_interval = nil, @meta = nil)
      super(@meta)
    end
  end

  class GetTaskPayloadResult < Result
    getter payload : Hash(String, JSON::Any)

    def initialize(@payload, @meta = nil)
      super(@meta)
    end
  end

  class TaskList
    include JSON::Serializable

    getter tasks : Array(Task)
    @[JSON::Field(key: "nextCursor")]
    getter next_cursor : String?
    getter total : Int64?

    def initialize(@tasks = [] of Task, @next_cursor = nil, @total = nil)
    end
  end
end
