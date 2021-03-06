define [
  'jquery'
  'underscore'
  'timezone'
  'compiled/calendar/commonEventFactory'
  'compiled/calendar/TimeBlockList'
  'jst/calendar/editCalendarEvent'
  'compiled/util/coupleTimeFields'
  'jquery.instructure_date_and_time'
  'jquery.instructure_forms'
  'jquery.instructure_misc_helpers'
  'vendor/date'
], ($, _, tz, commonEventFactory, TimeBlockList, editCalendarEventTemplate, coupleTimeFields) ->

  class EditCalendarEventDetails
    constructor: (selector, @event, @contextChangeCB, @closeCB) ->
      @currentContextInfo = null
      @$form = $(editCalendarEventTemplate({
        title: @event.title
        contexts: @event.possibleContexts()
        lockedTitle: @event.lockedTitle
        location_name: @event.location_name
      }))
      $(selector).append @$form

      @setupTimeAndDatePickers()

      @$form.submit @formSubmit
      @$form.find(".more_options_link").click @moreOptionsClick
      @$form.find("select.context_id").change @contextChange
      @$form.find("select.context_id").triggerHandler('change', false)

      # Hide the context selector completely if this is an existing event, since it can't be changed.
      if !@event.isNewEvent()
        @$form.find(".context_select").hide()

    contextInfoForCode: (code) ->
      for context in @event.possibleContexts()
        if context.asset_string == code
          return context
      return null

    activate: () =>
      @$form.find("select.context_id").change()

    getFormData: =>
      data = @$form.getFormData(object_name: 'calendar_event')
      data = _.omit(data, 'date', 'start_time', 'end_time')

      # check if input box was cleared for explicitly undated
      date = @$form.find('input[name=date]').data('date') if @$form.find('input[name=date]').val()
      if date
        start_time = @$form.find('input[name=start_time]').data('date')
        start_at = date.toString('yyyy-MM-dd')
        start_at += start_time.toString(' HH:mm') if start_time
        data.start_at = tz.parse(start_at)

        end_time = @$form.find('input[name=end_time]').data('date')
        end_at = date.toString('yyyy-MM-dd')
        end_at += end_time.toString(' HH:mm') if end_time
        data.end_at = tz.parse(end_at)

      data

    moreOptionsClick: (jsEvent) =>
      return if @event.object.parent_event_id

      jsEvent.preventDefault()
      params = return_to: window.location.href

      data = @getFormData()

      # override parsed input with user input (for 'More Options' only)
      data.start_date = @$form.find('input[name=date]').val()
      data.start_time = @$form.find('input[name=start_time]').val()
      data.end_time = @$form.find('input[name=end_time]').val()

      if data.title then params['title'] = data.title
      if data.location_name then params['location_name'] = data.location_name
      if data.start_date then params['start_date'] = data.start_date
      if data.start_time then params['start_time'] = data.start_time
      if data.end_time then params['end_time'] = data.end_time

      pieces = $(jsEvent.target).attr('href').split("#")
      pieces[0] += "?" + $.param(params)
      window.location.href = pieces.join("#")

    setContext: (newContext) =>
      @$form.find("select.context_id").val(newContext).triggerHandler('change', false)

    contextChange: (jsEvent, propagate) =>
      context = $(jsEvent.target).val()
      @currentContextInfo = @contextInfoForCode(context)
      @event.contextInfo = @currentContextInfo
      if @currentContextInfo == null then return

      if propagate != false
        @contextChangeCB(context)

      # Update the edit and more option urls
      moreOptionsHref = null
      if @event.isNewEvent()
        moreOptionsHref = @currentContextInfo.new_calendar_event_url
      else
        moreOptionsHref = @event.fullDetailsURL() + '/edit'
      @$form.find(".more_options_link").attr 'href', moreOptionsHref

    setupTimeAndDatePickers: () =>
      # select the appropriate fields
      $date = @$form.find(".date_field")
      $start = @$form.find(".time_field.start_time")
      $end = @$form.find(".time_field.end_time")

      # set them up as appropriate variants of datetime_field
      $date.date_field()
      $start.time_field()
      $end.time_field()

      # fill initial values of each field according to @event
      start = $.unfudgeDateForProfileTimezone(@event.startDate())
      end = $.unfudgeDateForProfileTimezone(@event.endDate())

      $date.data('instance').setDate(start)
      $start.data('instance').setTime(if @event.allDay then null else start)
      $end.data('instance').setTime(if @event.allDay then null else end)

      # couple start and end times so that end time will never precede start
      coupleTimeFields($start, $end)

    formSubmit: (jsEvent) =>
      jsEvent.preventDefault()

      data = @getFormData()
      location_name = data.location_name || ''

      params = {
        'calendar_event[title]': data.title ? @event.title
        'calendar_event[start_at]': if data.start_at then data.start_at.toISOString() else ''
        'calendar_event[end_at]': if data.end_at then data.end_at.toISOString() else ''
        'calendar_event[location_name]': location_name
      }

      if @event.isNewEvent()
        params['calendar_event[context_code]'] = data.context_code
        objectData =
          calendar_event:
            title: params['calendar_event[title]']
            start_at: if data.start_at then data.start_at.toISOString() else null
            end_at: if data.end_at then data.end_at.toISOString() else null
            location_name: location_name
            context_code: @$form.find(".context_id").val()
        newEvent = commonEventFactory(objectData, @event.possibleContexts())
        newEvent.save(params)
      else
        @event.title = params['calendar_event[title]']
        # I know this seems backward, fudging a date before saving, but the
        # event gets all out-of-whack if it's not...
        @event.start = $.fudgeDateForProfileTimezone(data.start_at)
        @event.end = $.fudgeDateForProfileTimezone(data.end_at)
        @event.location_name = location_name
        @event.save(params)

      @closeCB()
