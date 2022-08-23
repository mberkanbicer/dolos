# == Schema Information
#
# Table name: reports
#
#  id          :bigint           not null, primary key
#  error       :text(65535)
#  exit_status :integer
#  memory      :integer
#  run_time    :float(24)
#  status      :integer
#  stderr      :text(65535)
#  stdout      :text(65535)
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  dataset_id  :bigint           not null
#
# Indexes
#
#  index_reports_on_dataset_id  (dataset_id)
#
class Report < ApplicationRecord
  belongs_to :dataset

  RESULT_FILES = {
    metadata: "metadata.csv",
    files: "files.csv",
    kgrams: "kgrams.csv",
    pairs: "pairs.csv"
  }.freeze

  has_one_attached :metadata
  has_one_attached :files
  has_one_attached :kgrams
  has_one_attached :pairs

  enum :status, { unknown: 0, queued: 1, running: 2, failed: 3, error: 4, finished: 5}

  validate :dataset_is_analyzed, on: :create

  after_create :queue_analysis

  def dataset_is_analyzed
    return if dataset.nil?
    errors.add(:dataset, 'not yet analyzed') if !dataset.zipfile.analyzed?
  end

  def queue_analysis
    self.update(status: :queued)
    AnalyzeDatasetJob.perform_later(self)
  end

  def all_files_present?
    RESULT_FILES.keys.all?{ |attachment| self.send(attachment).attached? }
  end

  def collect_files_from(result_dir)
    RESULT_FILES.map do |name, file|
      path = result_dir.join(file)
      next if !File.readable?(path)
      self.send(name).attach(
        io: File.open(path),
        filename: file,
        content_type: 'text/csv',
        identify: false
      )
    end
  end
end
