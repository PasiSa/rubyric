require "tempfile"
require "fileutils"
require "rexml/document"
include REXML

class Exercise < ActiveRecord::Base
  belongs_to :course_instance
  has_many :groups, :order => 'name, id'
  has_many :submissions
  has_many :categories, {:dependent => :destroy, :order => 'position'}

  validates_presence_of :name

  # Feedback grouping options: exercise, sections, categories

  # Assigns submissions evenly to the given users
  # submissions: array of submission ids
  # users: array of user ids
  # exclusive: previous assignments are erased
  def assign(submission_ids, user_ids, exclusive = false)
    counter = 0
    n = user_ids.size

    users = User.find(user_ids)
    submissions = Submission.find(submission_ids, :conditions => ['exercise_id = ?', self.id])

    submissions.each do |submission|
      assistant = users[counter % n]

      if exclusive
        submission.assign_to_exclusive(assistant)
      else
        submission.assign_to(assistant)
      end

      counter += 1
    end
  end

  # Populates the rubric with some example data.
  # This erases the existing rubric.
  def initialize_example
    # Destroy existing rubric
    categories.clear

    category = Category.new({:name => 'New part (click to edit)', :position => 1, :exercise_id => id})
    category.save

    section = Section.new({:name => 'New section (click to edit)', :position => 1})
    category.sections << section

    item = Item.new({:name => 'New item (click to edit)', :position => 1})
    section.items << item

    phrase1 = Phrase.new({:content => 'Feedback (click to edit)', :feedbacktype => 'Bad', :position => 1})
    phrase2 = Phrase.new({:content => 'Feedback (click to edit)', :feedbacktype => 'Good', :position => 2})
    item.phrases << phrase1
    item.phrases << phrase2
  end

  # Load rubric from an XML file.
  # This erases the existing rubric.
  def load_xml(file)
    # Destroy existing rubric
    categories.clear

    # Parse XML
    doc = REXML::Document.new(file)

    category_counter = 0

    # Categories
    doc.each_element('rubric/category') do |category|
      category_counter += 1
      new_category = Category.new({:name => category.attributes['name'], :position => category_counter})
      new_category.weight = category.attributes['weight'] if category.attributes['weight']
      categories << new_category
      section_counter = 0
      sgo_counter = 0

      # Sections
      category.each_element('section') do |section|
        section_counter += 1
        new_section = Section.new({:name => section.attributes['name'], :position => section_counter})
        new_section.weight = section.attributes['weight'] if section.attributes['weight']
        new_category.sections << new_section
        item_counter = 0

        #Items
        section.each_element('item') do |item|
          item_counter += 1
          new_item = Item.new({:name => item.attributes['name'], :position => item_counter})
          new_section.items << new_item
          phrase_counter = 0
          igo_counter = 0

          # Phrases
          item.each_element('phrase') do |phrase|
            phrase_counter += 1
            new_phrase = Phrase.new({:content => phrase.text.strip, :feedbacktype => phrase.attributes['type'], :position => phrase_counter})
            new_item.phrases << new_phrase
          end

          # Item grading options
          item.each_element('grade') do |grading_option|
            igo_counter += 1
            new_grading_option = ItemGradingOption.new({:text => grading_option.text.strip, :position => igo_counter})
            new_item.item_grading_options << new_grading_option
          end
        end # items

        # Section grading options
        section.each_element('grade') do |grading_option|
          sgo_counter += 1
          new_grading_option = SectionGradingOption.new({:text => grading_option.text.strip, :points => grading_option.attributes['points'], :position => sgo_counter})
          new_section.section_grading_options << new_grading_option
        end

      end # sections
    end # categories

    # Properties
    positive_caption_element = XPath.first(doc, "/rubric/positive-caption")
    self.positive_caption = positive_caption_element.text.strip if positive_caption_element and positive_caption_element.text

    negative_caption_element = XPath.first(doc, "/rubric/negative-caption")
    self.negative_caption = negative_caption_element.text.strip if negative_caption_element and negative_caption_element.text

    neutral_caption_element = XPath.first(doc, "/rubric/neutral-caption")
    self.neutral_caption = neutral_caption_element.text.strip if neutral_caption_element and neutral_caption_element.text

    feedback_grouping_element = XPath.first(doc, "/rubric/feedback-grouping")
    self.feedbackgrouping = feedback_grouping_element.text.strip if feedback_grouping_element and feedback_grouping_element.text

    final_comment_element = XPath.first(doc, "/rubric/final-comment")
    self.finalcomment = final_comment_element.text.strip if final_comment_element and final_comment_element.text

    # Save
    save
  end


  def generate_xml
    doc = Document.new
    root = doc.add_element 'rubric'

    # Categories
    categories.each do |category|
      category_element = root.add_element 'category', {'name' => category.name, 'weight' => category.weight}

      # Section
      category.sections.each do |section|
        section_element = category_element.add_element 'section', {'name' => section.name, 'weight' => section.weight}

        # Items
        section.items.each do |item|
          item_element = section_element.add_element 'item', {'name' => item.name}

          # Phrases
          item.phrases.each do |phrase|
            phrase_element = item_element.add_element 'phrase', {'type' => phrase.feedbacktype}
            phrase_element.add_text phrase.content
          end

          # Item grades
          item.item_grading_options.each do |grading_option|
            item_go_element = item_element.add_element 'grade'
            item_go_element.add_text grading_option.text
          end

        end

        # Section grades
        section.section_grading_options.each do |grading_option|
          section_go_element = section_element.add_element 'grade', {'points' => grading_option.points}
          section_go_element.add_text grading_option.text
        end

      end
    end

    # Properties
    final_comment = root.add_element 'final-comment'
    final_comment.add_text self.finalcomment

    positive_caption = root.add_element 'positive-caption'
    positive_caption.add_text self.positive_caption

    negative_caption = root.add_element 'negative-caption'
    negative_caption.add_text self.negative_caption

    neutral_caption = root.add_element 'neutral-caption'
    neutral_caption.add_text self.neutral_caption

    feedback_grouping = root.add_element 'feedback-grouping'
    feedback_grouping.add_text self.feedbackgrouping

    # Write the XML, intendation = 2 spaces
    output = ""
    doc.write(output)

    return output
  end

  # Returs a grade distribution histogram [[grade,count],[grade,count],...]
  def grade_distribution(grader = nil)
    if grader
      reviews = Review.find(:all, :joins => 'FULL JOIN submissions ON reviews.submission_id = submissions.id ', :conditions => [ 'exercise_id = ? AND user_id = ? AND calculated_grade IS NOT NULL', self.id, grader.id ])
    else
      reviews = Review.find(:all, :joins => 'FULL JOIN submissions ON reviews.submission_id = submissions.id ', :conditions => [ 'exercise_id = ?  AND calculated_grade IS NOT NULL', self.id ])
    end

    # group reviews by grade  [ [grade,[review,review,...]], [grade,[review,review,...]], ...]
    reviews_by_grade = reviews.group_by{|review| review.calculated_grade}

    # count reviews in each bin [ [grade, count], [grade,count], ... ]
    histogram = reviews_by_grade.collect { |grade, stats| [grade,stats.size] }

    # sort by grade
    histogram.sort { |x,y| x[0] <=> y[0] }
  end

  # Assign submissions to assistants
  # csv: student, assistant
  def batch_assign(csv)
    counter = 0

    # Make an array of lines
    array = csv.split(/\r?\n|\r(?!\n)/)

    Exercise.transaction do
      array.each do |line|
        parts = line.split(',',2).map { |s| s.strip }
        next if parts.size < 1

        submission_studentnumber = parts[0]
        assistant_studentnumber = parts[1]

        # Find submissions that belong to the student
        submissions = Submission.find(:all, :conditions => [ "groups.exercise_id = ? AND users.studentnumber = ?", self.id, submission_studentnumber], :joins => {:group => :users})
        grader = User.find_by_studentnumber(assistant_studentnumber)

        next unless grader

        # Assign those submissions
        submissions.each do |submission|
          counter += 1 if submission.assign_once_to(grader)
        end
      end

      return counter
    end
  end

  def archive(options = {})
    only_latest = options.include? :only_latest

    archive = Tempfile.new('rubyric-archive')

    temp_dir = "/tmp"

    # Create the actual content directory so that it has a sensible name in the archive
    content_dir_name = "rubyric-exercise-#{self.id}"
    unless File.directory? "#{temp_dir}/#{content_dir_name}"
      Dir.mkdir "#{temp_dir}/#{content_dir_name}"
    end

    # Add contents
    groups.each do |group|
      group.submissions.each do |submission|

        # Link the submissionn
        source_filename = submission.full_filename
        target_filename = "#{temp_dir}/#{content_dir_name}/#{group.name}-#{submission.created_at.strftime('%Y%m%d%H%M%S')}"
        target_filename << ".#{submission.extension}" unless submission.extension.blank?

        if File.exist?(source_filename)
          FileUtils.cp(source_filename, target_filename)
        end

        # Take only one file per group?
        if only_latest
          break
        end
      end
    end

    # Archive the folder
    system("tar -zc --directory #{temp_dir} --file #{archive.path()} #{content_dir_name}")

    return archive
  end

  # Creates an example course, instance and submissions.
  def create_example_submissions
    example_submission_file = "#{SUBMISSIONS_PATH}/example.pdf"
    example_submission_file = nil unless File.exists?(example_submission_file)

    submission_path = "#{SUBMISSIONS_PATH}/#{self.id}"
    FileUtils.makedirs(submission_path)

    # Create groups and submissions
    for i in (1..10)
      group = Group.create(:exercise_id => self.id, :name => "Group #{i}")

      user = User.find_by_studentnumber(i.to_s.rjust(5,'0'))
      group.users << user if user

      submission = Submission.create(:exercise_id => self.id, :group_id => group.id, :extension => 'pdf', :filename => 'example.pdf')

      FileUtils.ln_s(example_submission_file, "#{submission_path}/#{submission.id}.pdf") if example_submission_file
    end
  end


  # Will be run in background by delayed job
  def self.deliver_reviews(review_ids)
    # Send all reviews
    reviews = Review.find(:all, :conditions => {:id => review_ids, :status => 'mailing'})

    logger.info "Sending #{reviews.size} reviews"

    reviews.each do |review|
      Mailer.deliver_review(review)
    end
  end

  def disk_space
    path = "#{SUBMISSIONS_PATH}/#{self.id}"
    `du -s #{path}`.split("\t")[0].to_i
  end

end
