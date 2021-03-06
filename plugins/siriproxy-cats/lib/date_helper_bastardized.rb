
# Reports the approximate distance in time between two Time, Date or DateTime objects or integers as seconds.
# Set <tt>include_seconds</tt> to true if you want more detailed approximations when distance < 1 min, 29 secs.
# Distances are reported based on the following table:
#
#   0 <-> 29 secs                                                             # => less than a minute
#   30 secs <-> 1 min, 29 secs                                                # => 1 minute
#   1 min, 30 secs <-> 44 mins, 29 secs                                       # => [2..44] minutes
#   44 mins, 30 secs <-> 89 mins, 29 secs                                     # => about 1 hour
#   89 mins, 30 secs <-> 23 hrs, 59 mins, 29 secs                             # => about [2..24] hours
#   23 hrs, 59 mins, 30 secs <-> 41 hrs, 59 mins, 29 secs                     # => 1 day
#   41 hrs, 59 mins, 30 secs  <-> 29 days, 23 hrs, 59 mins, 29 secs           # => [2..29] days
#   29 days, 23 hrs, 59 mins, 30 secs <-> 59 days, 23 hrs, 59 mins, 29 secs   # => about 1 month
#   59 days, 23 hrs, 59 mins, 30 secs <-> 1 yr minus 1 sec                    # => [2..12] months
#   1 yr <-> 1 yr, 3 months                                                   # => about 1 year
#   1 yr, 3 months <-> 1 yr, 9 months                                         # => over 1 year
#   1 yr, 9 months <-> 2 yr minus 1 sec                                       # => almost 2 years
#   2 yrs <-> max time or date                                                # => (same rules as 1 yr)
#
# With <tt>include_seconds</tt> = true and the difference < 1 minute 29 seconds:
#   0-4   secs      # => less than 5 seconds
#   5-9   secs      # => less than 10 seconds
#   10-19 secs      # => less than 20 seconds
#   20-39 secs      # => half a minute
#   40-59 secs      # => less than a minute
#   60-89 secs      # => 1 minute
#
# ==== Examples
#   from_time = Time.now
#   distance_of_time_in_words(from_time, from_time + 50.minutes)        # => about 1 hour
#   distance_of_time_in_words(from_time, 50.minutes.from_now)           # => about 1 hour
#   distance_of_time_in_words(from_time, from_time + 15.seconds)        # => less than a minute
#   distance_of_time_in_words(from_time, from_time + 15.seconds, true)  # => less than 20 seconds
#   distance_of_time_in_words(from_time, 3.years.from_now)              # => about 3 years
#   distance_of_time_in_words(from_time, from_time + 60.hours)          # => 3 days
#   distance_of_time_in_words(from_time, from_time + 45.seconds, true)  # => less than a minute
#   distance_of_time_in_words(from_time, from_time - 45.seconds, true)  # => less than a minute
#   distance_of_time_in_words(from_time, 76.seconds.from_now)           # => 1 minute
#   distance_of_time_in_words(from_time, from_time + 1.year + 3.days)   # => about 1 year
#   distance_of_time_in_words(from_time, from_time + 3.years + 6.months) # => over 3 years
#   distance_of_time_in_words(from_time, from_time + 4.years + 9.days + 30.minutes + 5.seconds) # => about 4 years
#
#   to_time = Time.now + 6.years + 19.days
#   distance_of_time_in_words(from_time, to_time, true)     # => about 6 years
#   distance_of_time_in_words(to_time, from_time, true)     # => about 6 years
#   distance_of_time_in_words(Time.now, Time.now)           # => less than a minute
#

# config.i18n.load_path += Dir[Rails.root.join('locales', '*.{rb,yml}').to_s]
# config.i18n.default_locale = :da
# config.i18n.locale = :da
require 'i18n'

I18n.load_path = [ File.join(File.dirname(__FILE__), "en.yml") ]
I18n.default_locale = :en

def distance_of_time_in_words(from_time, to_time = 0, include_seconds = false, options = {})
  from_time = from_time.to_time if from_time.respond_to?(:to_time)
  to_time = to_time.to_time if to_time.respond_to?(:to_time)
  distance_in_minutes = (((to_time - from_time).abs)/60).round
  distance_in_seconds = ((to_time - from_time).abs).round

  I18n.with_options :locale => options[:locale], :scope => :'datetime.distance_in_words' do |locale|
    case distance_in_minutes
      when 0..1
        return distance_in_minutes == 0 ?
               locale.t(:less_than_x_minutes, :count => 1) :
               locale.t(:x_minutes, :count => distance_in_minutes) unless include_seconds

        case distance_in_seconds
          when 0..4   then locale.t :less_than_x_seconds, :count => 5
          when 5..9   then locale.t :less_than_x_seconds, :count => 10
          when 10..19 then locale.t :less_than_x_seconds, :count => 20
          when 20..39 then locale.t :half_a_minute
          when 40..59 then locale.t :less_than_x_minutes, :count => 1
          else             locale.t :x_minutes,           :count => 1
        end

      when 2..44           then locale.t :x_minutes,      :count => distance_in_minutes
      when 45..89          then locale.t :about_x_hours,  :count => 1
      when 90..1439        then locale.t :about_x_hours,  :count => (distance_in_minutes.to_f / 60.0).round
      when 1440..2519      then locale.t :x_days,         :count => 1
      when 2520..43199     then locale.t :x_days,         :count => (distance_in_minutes.to_f / 1440.0).round
      when 43200..86399    then locale.t :about_x_months, :count => 1
      when 86400..525599   then locale.t :x_months,       :count => (distance_in_minutes.to_f / 43200.0).round
      else
        fyear = from_time.year
        fyear += 1 if from_time.month >= 3
        tyear = to_time.year
        tyear -= 1 if to_time.month < 3
        leap_years = (fyear > tyear) ? 0 : (fyear..tyear).count{|x| Date.leap?(x)}
        minute_offset_for_leap_year = leap_years * 1440
        # Discount the leap year days when calculating year distance.
        # e.g. if there are 20 leap year days between 2 dates having the same day
        # and month then the based on 365 days calculation
        # the distance in years will come out to over 80 years when in written
        # english it would read better as about 80 years.
        minutes_with_offset         = distance_in_minutes - minute_offset_for_leap_year
        remainder                   = (minutes_with_offset % 525600)
        distance_in_years           = (minutes_with_offset / 525600)
        if remainder < 131400
          locale.t(:about_x_years,  :count => distance_in_years)
        elsif remainder < 394200
          locale.t(:over_x_years,   :count => distance_in_years)
        else
          locale.t(:almost_x_years, :count => distance_in_years + 1)
        end
    end
  end
end

# Like <tt>distance_of_time_in_words</tt>, but where <tt>to_time</tt> is fixed to <tt>Time.now</tt>.
#
# ==== Examples
#   time_ago_in_words(3.minutes.from_now)       # => 3 minutes
#   time_ago_in_words(Time.now - 15.hours)      # => about 15 hours
#   time_ago_in_words(Time.now)                 # => less than a minute
#
#   from_time = Time.now - 3.days - 14.minutes - 25.seconds
#   time_ago_in_words(from_time)      # => 3 days
#
def time_ago_in_words(from_time, include_seconds = false)
  distance_of_time_in_words(from_time, Time.now, include_seconds)
end


## Dependancies. Yay!

module I18n
  def self.with_options(options)
    yield ActiveSupport::OptionMerger.new(self, options)
  end
end

class Hash
  # Returns a new hash with +self+ and +other_hash+ merged recursively.
  def deep_merge(other_hash)
    dup.deep_merge!(other_hash)
  end

  # Returns a new hash with +self+ and +other_hash+ merged recursively.
  # Modifies the receiver in place.
  def deep_merge!(other_hash)
    other_hash.each_pair do |k,v|
      tv = self[k]
      self[k] = tv.is_a?(Hash) && v.is_a?(Hash) ? tv.deep_merge(v) : v
    end
    self
  end
end

module ActiveSupport
  class OptionMerger #:nodoc:
    instance_methods.each do |method|
      undef_method(method) if method !~ /^(__|instance_eval|class|object_id)/
    end

    def initialize(context, options)
      @context, @options = context, options
    end

    private
      def method_missing(method, *arguments, &block)
        if arguments.last.is_a?(Proc)
          proc = arguments.pop
          arguments << lambda { |*args| @options.deep_merge(proc.call(*args)) }
        else
          arguments << (arguments.last.respond_to?(:to_hash) ? @options.deep_merge(arguments.pop) : @options.dup)
        end

        @context.__send__(method, *arguments, &block)
      end
  end
end

