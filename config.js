const fs = require('fs');

module.exports = () => {
   let contents = fs.readFileSync('./config.yaml', {encoding: 'utf8'});
   return contents;
}
