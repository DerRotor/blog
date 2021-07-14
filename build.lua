local arrr = require 'arrr'
local restia = require 'restia'
local shapeshift = require 'shapeshift'

local params do
	local is = shapeshift.is
	local parse = arrr {
		{ "Output directory", "--output", "-o", 'directory' };
		{ "Input directory", "--input", "-i", 'directory' };
		{ "Copy directory", "--copy", "-c", 'directory', 'repeatable' };
		{ "Delete everything first", "--delete", "-d" };
	}
	local validate = shapeshift.table {
		output = shapeshift.default("out", is.string);
		input = shapeshift.default(".", is.string);
		copy = shapeshift.default({}, shapeshift.all{
			is.table,
			shapeshift.each(is.string)
		});
		delete = shapeshift.is.boolean;
	}
	params = assert(validate(parse{...}))
end

local config = restia.config.bind('config', {
	(require 'restia.config.readfile');
	(require 'restia.config.lua');
	(require 'restia.config.yaml');
})
package.loaded.config = config

local templates = restia.config.bind('templates', {
	(require 'restia.config.skooma');
	(require 'restia.config.moonhtml');
})
package.loaded.templates = templates

local function render_post(file)
	local post = restia.config.post(from)

	restia.utils.mkdir(to:gsub("[^/]+$", ""))
	local outfile = assert(io.open(to, 'wb'))
	outfile:write(body)
	outfile:close()
end

local tree = {}

for i, path in ipairs(params.copy) do
	restia.utils.deepinsert(tree, restia.utils.fs2tab(path), restia.utils.readdir(path))
end

local validate_head do
	local is = shapeshift.is
	validate_head = shapeshift.table {
		__extra = 'keep';
		title = is.string;
		date = shapeshift.matches("%d%d%d%d%-%d%d%-%d%d");
	}
end

for file in restia.utils.files(params.input, "%.post$") do
	post = restia.config.post(file)

	assert(validate_head(post.head))

	local template if post.head.template then
		template = templates[post.head.template]
	elseif templates.main then
		template = templates.main
	end

	local body if template then
		body = restia.utils.deepconcat(template(post.body, post.head))
	else
		body = post.body
	end

	local path = string.format("%s.%s\0html", 
		post.head.date
			:gsub("%-", "."),
		post.head.title
			:gsub(' ', '_')
			:lower()
			:gsub('[^a-z0-9-_]', '')
	)
	restia.utils.deepinsert(tree, path, body)
end

if params.delete then
	print("Deleting: "..params.output)
	restia.utils.delete(params.output)
end

restia.utils.builddir(params.output, tree)
