class Availability < ActiveRecord::Base
  has_paper_trail

  belongs_to :person

  after_create :cancel_duplicates

  validates_presence_of :person, :status, :start_time, :end_time
  validates_chronology :start_time, :end_time

  STATUS_CHOICES = [ 'Available', 'Unavailable', "Cancelled" ]

  # Available the entire event
  scope :for_time_span, ->(range) { where("end_time >= ?", range.last).
                               where("start_time <= ?", range.first) }

  # Available part of event
  scope :partially_available, ->(range) { where("? > end_time AND end_time > ? OR ? > start_time AND start_time > ?", range.last, range.first, range.last, range.first) }

  scope :active, -> { where(status: ['Available', 'Unavailable']).joins(:person).where(people: {status: "Active"}) }
  scope :available, -> { where(status: "Available")}
  scope :unavailable, -> { where(status: "Unavailable")}

  scope :in_the_past, -> { where("start_time <= ?", Time.zone.now) }

  # These scopes tie the application to postgres, as they rely
  # on its range data type implementation. The ranges are left_bound closed
  # and right_bound open, as specified by the argument '[)'
  # reference: https://www.postgresql.org/docs/current/static/rangetypes.html
  scope :overlapping, lambda { |range|  
    where("tsrange(start_time, end_time, '[)') && tsrange(TIMESTAMP?, TIMESTAMP?, '[)')",
          range.first, range.last) }

  scope :containing, lambda { |range|
    where("tsrange(start_time, end_time, '[)') @> tsrange(TIMESTAMP?, TIMESTAMP?, '[)')",
          range.first, range.last) }

  scope :contained_in, lambda { |range|
    where("tsrange(start_time, end_time, '[)') <@ tsrange(TIMESTAMP?, TIMESTAMP?, '[)')",
          range.first, range.last) }

  def to_s
    "Recorded #{status}\n start #{start_time} \n end #{end_time} \n description #{description}"
  end

  def partially_available?(event)
    return false if event.nil? || (event.end_time <= self.end_time && event.start_time >= self.start_time)
    (event.end_time >= self.end_time && self.end_time >= event.start_time) || (event.end_time >= self.start_time && self.start_time >= event.start_time)
  end

  def self.process_data
    availabilities = Availability.available
    start_time = availabilities.map(&:start_time).min.to_datetime
    end_time = availabilities.map(&:end_time).max.to_datetime
    data = []
    data <<
      (start_time..end_time).map do |date|
        count = Availability.where('date(start_time) <= ? AND date(end_time) >= ?', date, date).count
        { 'Date' => date, 'Count' => count }
      end
  end

  private

  def cancel_duplicates
    previous_availabilities = person.availabilities.for_time_span(start_time..end_time)
    previous_availabilities.each do |a|
      if start_time == a.start_time && end_time == a.end_time
        a.update(status: "Cancelled") unless self == a
      end
    end
  end
end
