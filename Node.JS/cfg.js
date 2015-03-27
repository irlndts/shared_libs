// Парсер конфигурационных файлов (синхронный!)

/*
 * fs	- File System (http://nodejs.org/docs/v0.3.1/api/fs.html)
 * path - Forms the path to modules (http://nodejs.org/docs/v0.3.1/api/path.html)
 */

var fs		= require('fs');
var path	= require('path'); 

// Анализ парамтеров из конфига , регулярными выражениями
var regex = {
	param: /^\s*([\w\.\-\_]+)\s*=\s*(.*?)\s*$/,
	comment: /^\s*;.*$|^\s*#.*$/,
	quotes: /^"(.*)"$/
};

// Создать сам обработчик модуля
module.exports.parseConfig = function(file) {
	if (path.existsSync(file)) {
		return parse(fs.readFileSync(file, 'utf8'));
	} else {
		console.log('Can not found config file '+file);
		process.exit(1);
	};
};

// Парсит конфигурационный файл
function parse(data) {
	var value = {};
	var lines = data.split(/\r\n|\r|\n/);
	var section = null;
	lines.forEach(function(line){
		if(regex.comment.test(line)) {
			// переходит к следующей строке
			return;
		} else if(regex.param.test(line)) {
			var match = line.match(regex.param);
			var vname = match[1];
			var vval = match[2];
			// Убрать комменты
			if (regex.quotes.test(vval)) {
				var m = vval.match(regex.quotes);
				vval = m[1];
			};

			value[vname] = vval;
		};
	});
	return value;
}