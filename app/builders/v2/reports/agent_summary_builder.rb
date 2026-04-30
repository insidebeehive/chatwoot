class V2::Reports::AgentSummaryBuilder < V2::Reports::BaseSummaryBuilder
  pattr_initialize [:account!, :params!]

  def build
    load_data
    prepare_report
  end

  private

  attr_reader :conversations_count, :resolved_count,
              :avg_resolution_time, :avg_first_response_time, :avg_reply_time

  def fetch_conversations_count
    # Count conversations where the agent actually responded (sent the first reply),
    # not just who was assigned — avoids crediting offline agents who never attended.
    account.reporting_events
           .where(name: 'first_response', created_at: range)
           .group(:user_id)
           .count
  end

  def prepare_report
    account.account_users.map do |account_user|
      build_agent_stats(account_user)
    end
  end

  def build_agent_stats(account_user)
    user_id = account_user.user_id
    {
      id: user_id,
      conversations_count: conversations_count[user_id] || 0,
      resolved_conversations_count: resolved_count[user_id] || 0,
      avg_resolution_time: avg_resolution_time[user_id],
      avg_first_response_time: avg_first_response_time[user_id],
      avg_reply_time: avg_reply_time[user_id]
    }
  end

  def group_by_key
    :user_id
  end
end
