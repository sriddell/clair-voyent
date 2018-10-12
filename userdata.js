const fs = require('fs');

module.exports = (slsConfig) => {
  stage = slsConfig.service.provider.stage
  let contents = fs.readFileSync('./userdata.txt', {encoding: 'utf8'});
  contents = contents.replace('{{stage}}', stage)
  let configure = fs.readFileSync('./configure.py', {encoding: 'utf8'});
  contents = contents.replace('{{configure.py}}', 'cat << EOF > /configure.py\n' + configure + '\nEOF')
  return contents;
}
