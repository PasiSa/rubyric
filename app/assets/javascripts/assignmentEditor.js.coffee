class User
  constructor: (data) ->
    @id = data['id']
    @firstname = data['firstname'] || ''
    @lastname = data['lastname'] || ''
    @email = data['email'] || ''
    if @firstname.length + @lastname.length > 0
      @name = "#{@firstname} #{@lastname}"
    else
      @name = @email
    
    @studentnumber = data['studentnumber'] || ''
    @assignments = ko.observableArray()
    

class Group
  constructor: (data, users) ->
    @id = data['id']
    @selected = ko.observable(false)
    @url = data['url']
    @visible = ko.observable(true)

    # Set students
    groupname = []
    for member_data in data['group_members']
      member_string = member_data['name'] || ''
      member_string += " (#{member_data['studentnumber']})" if member_data['studentnumber']?.length > 0
      member_string = member_data['email'] || '' if member_string.length < 1
      groupname.push(member_string)
      
    @name = groupname.join(', ')
    @name = 'Untitled group' if @name.length < 1

    # Set reviewers
    @reviewers = ko.observableArray()
    for user_id in data['reviewer_ids']
      reviewer = users[user_id]
      if reviewer
        @reviewers.push(reviewer)
        reviewer.assignments.push(this)
    

  assignTo: (reviewer) ->
    return if @reviewers.indexOf(reviewer) >= 0 # Ignore duplicates
    
    @reviewers.push(reviewer)
    reviewer.assignments.push(this)

  removeAssignment: (reviewer) ->
    @reviewers.remove(reviewer)
    reviewer.assignments.remove(this)
  
  clickAssign: () ->
    modal = $('#modalAssign')
    modal.data('group', this)
    modal.modal()

  setVisible: () ->
    @visible(true)

  setInvisible: () ->
    @visible(false)
    @selected(false)

  visible: () ->
    @visible


class Exercise
  constructor: (data) ->
    @id = data['id']
    @name = data['name'] || ''
    
class Submission
  constructor: (data) ->
    @id = data['id']
    @group_id = data['group_id']
    @exercise_id = data['exercise_id']

class AssignmentEditor
  constructor: (data) ->
    @currentReviewer = ko.observable()
    @filterBy = ko.observable()
    
    @users_by_id = {}
    @teachers = []
    @assistants = []
    @reviewers = []  # = @teachers + @assistants
    @groups = []
    @submissions = []
    @exercises = []
    
    for user in data['users']
      @users_by_id[user.id] = new User(user)
    
    for user_id in data['teachers']
      @teachers.push(@users_by_id[user_id])
      @reviewers.push(@users_by_id[user_id])
    
    for user_id in data['assistants']
      @assistants.push(@users_by_id[user_id])
      @reviewers.push(@users_by_id[user_id])
    
    for group in data['groups']
      @groups.push(new Group(group, @users_by_id))

    for submission in data['submissions']
      @submissions.push(new Submission(submission))
    
    for exercise in data['exercises']
      @exercises.push(new Exercise(exercise))
  
    # Event handlers
    $(document).on('click', '.removeAssignment', @removeAssignment)
    #$(window).bind 'beforeunload', => return "You have unsaved changes. Leave anyway?" unless @saved
  
  
  clickFilter: ->
    if @filterBy() == 'all'
      for group in @groups
        group.setVisible()
    else
      for group in @groups
        group.setInvisible()
        for submission in @submissions
          if group.id == submission.group_id and @filterBy() == submission.exercise_id
            group.setVisible()

  clickSelectAll: ->
    for group in @groups
      if group.visible()
        group.selected(true)
  
  
  clickSelectNone: ->
    for group in @groups
      if group.visible()
        group.selected(false)
  
  clickAssign: ->
    if @currentReviewer() == 'assistants'
      users = @assistants
    else if @currentReviewer() == 'evenly'
      users = @reviewers
    else
      user = @users_by_id[@currentReviewer()]
      return unless user
      users = [user]
      
    return if users.length < 1
    
    index = 0
    for group in @groups
      continue unless group.selected()
      group.assignTo(users[index])
      index++
      index = 0 if index >= users.length
  
  
  clickModalAssign: (user) ->
    modal = $('#modalAssign')
    group = modal.data('group')
    return unless group
  
    group.assignTo(user)
    
    modal.modal('hide')
  
  
  removeAssignment: ->
    group = ko.contextFor(this).$parent
    reviewer = ko.dataFor(this)
    
    group.removeAssignment(reviewer)
    
    return false
  
  
  clickSave: ->
    assignments = {}
    
    for group in @groups
      assignments[group.id] = []
      for reviewer in group.reviewers()
        assignments[group.id].push(reviewer.id)
  
  
    $('#save-button').addClass('busy')
    url = $('#assign-groups').data('url')
    
    $.ajax
      type: "PUT"
      url: url
      data: JSON.stringify({assignments: assignments})
      contentType: 'application/json'
      dataType: 'json'
      error: (error) ->
        $('#save-button').removeClass('busy')
        #alert("Failed to save")
      success: -> $('#save-button').removeClass('busy')
      


jQuery ->
  assignmentEditor = new AssignmentEditor(window.group_data)
  ko.applyBindings(assignmentEditor, document.body)
  $('#assign-groups').removeClass('busy')
