module Todo

# Julia package for using and working with the todo.txt format (defined [here](https://github.com/todotxt/todo.txt))

using Dates: Dates, Date, format, @dateformat_str


#todo"more accurately parse description into a vector of strings, projects, contexts, and tags"
struct TodoTask
	isComplete::Bool
	priority::Union{Char, Nothing}
	completed::Union{Date, Nothing}
	created::Union{Date, Nothing}
	description::String
	
	function TodoTask(isComplete::Bool, priority::Union{Char, Nothing}, completed::Union{Date, Nothing}, created::Union{Date, Nothing}, description::AbstractString)
		!isnothing(completed) && !isnothing(created) && completed < created && error("TodoTask cannot be completed before it was created")
		!isnothing(completed) && !isComplete && error("TodoTask cannot have a completion date yet be marked incomplete")
		isnothing(priority) || 'A' <= priority <= 'Z' || error("TodoTask priority must a capital letter [A-Z]")
		
		desc = String(description)
		isnothing(match(r"^x ", desc)) || error("TodoTask description may not begin with a completion marking, e.g. `x `")
		isnothing(match(r"^\([A-Z]\) ", desc)) || error("TodoTask description may not begin with a priority, e.g. `(A) `")
		isnothing(match(r"^[\d]{4}-[\d]{2}-[\d]{2} ", desc)) || error("TodoTask description may not begin with a date, e.g. `2019-01-23 `")
		
		#todo"ensure desc doesnt contain control chars"
		#todo"ensure tags, contexts, projects contain no whitespace chars"
		
		return new(isComplete, priority, completed, created, desc)
	end
end

function TodoTask(line::AbstractString = ""; kwargs...)
	foreach(k -> k in fieldnames(TodoTask) || error("Keyword argument $(k) is not a valid field for TodoTask ($(fieldnames(TodoTask)...))"), keys(kwargs))
	
	m = match(r"^(?:(x)[ ]+)?(?:\(([A-Z])\)[ ]+)?(?:([\d]{4}-[\d]{2}-[\d]{2})[ ]+)?(?:([\d]{4}-[\d]{2}-[\d]{2})[ ]+)?(.*)$", escape_string(line))
	isnothing(m) && error("Invalid line used to construct a TodoTask `$(line)`")
	
	(isC, pri, com, cre, des) = m.captures
	isC = isnothing(isC) ? false : true
	pri = isnothing(pri) ? nothing : pri[1]
	com = isnothing(com) ? nothing : Date(com, dateformat"yyyy-mm-dd")
	cre = isnothing(cre) ? nothing : Date(cre, dateformat"yyyy-mm-dd")
	des = unescape_string(des)
	
	return TodoTask(
		get(kwargs, :isComplete, isC), 
		get(kwargs, :priority, pri), 
		get(kwargs, :completed, com), 
		get(kwargs, :created, cre), 
		get(kwargs, :description, des),
	)
end

isComplete(task::TodoTask) = task.isComplete
priority(task::TodoTask) = task.priority
completed(task::TodoTask) = task.completed
created(task::TodoTask) = task.created
description(task::TodoTask) = task.description
projects(task::TodoTask) = collect(eachmatch(r"(?:^| )\+([^ ]+)", task.description))
contexts(task::TodoTask) = collect(eachmatch(r"(?:^| )@([^ ]+)", task.description))
tags(task::TodoTask) = map(m -> m.captures[1] => m.captures[2], collect(eachmatch(r"(?:^| )([^ :]+):([^ ]+)", task.description)))


Base.string(task::TodoTask) = join((
	task.isComplete ? "x " : "",
	!isnothing(task.priority) ? "($(task.priority)) " : "",
	!isnothing(task.completed) ? format(task.completed, dateformat"yyyy-mm-dd ") : "",
	!isnothing(task.created) ? format(task.created, dateformat"yyyy-mm-dd ") : "",
	escape_string(task.description)
))


function load(filePath)
	return open(filePath) do file
		return map(line -> TodoTask(unescape_string(line)), filter(!isempty, readlines(file)))
	end
end

function save(filePath, todos; format = :todo, kwargs...)
	format in (:todo, :markdown) || error("`$(format)` is not a valid format for saving.")
	
	open(filePath, "w+") do file
		if format === :todo
			foreach(task::TodoTask -> println(file, string(task)), todos)
		elseif format === :markdown
			println(file, get(kwargs, :heading, "## Todos"))
			println(file)
			foreach(todos) do todo::TodoTask
				print(file, "- [$(todo.isComplete ? 'x' : ' ')] ")
				println(file, replace(todo.description, '\n' => "  \n"))
			end
			println(file)
		end
	end
	return nothing
end


_todos = Dict{TodoTask, Int}()

todos() = collect(keys(_todos))
todo_hits() = filter(((todo, hits),) -> hits > 0, _todos)
reset_hits() = foreach(key -> _todos[key] = 0, keys(_todos))
clear_todos() = empty!(_todos)


macro todo_str(line::String) ; return _add_todo(line, __source__, __module__) ; end

function _add_todo(line::String, src::LineNumberNode, mod::Module)
	# do nothing when file field is not provided or when in the REPL
	isnothing(src.file) && return quote end
	isnothing(match(r"^REPL\[\d+\]$", string(src.file))) || return quote end
	
	task = TodoTask(line)
	
	#todo"escape spaces in profile and context strings"
	
	project = string(mod)
	project = replace(project, r"^Main\." => "")
	task = project in projects(task) ? task : TodoTask(unescape_string(string(task)), description = "$(task.description) +$(project)")
	
	context = "$(string(src.file)):$(src.line)"
	task = context in contexts(task) ? task : TodoTask(unescape_string(string(task)), description = "$(task.description) @$(context)")
	
	line = unescape_string(string(task))
	task = TodoTask(line)
	haskey(Todo._todos, task) || push!(Todo._todos, task => 0)
	
	return Todo.TRACK_TODOS ? :(Todo._todos[TodoTask($(line))] += 1 ; nothing) : nothing
end


function __init__()
	global TRACK_TODOS = isdefined(Main, :TRACK_TODOS) ? (Main.TRACK_TODOS === true) : isinteractive()
end

end