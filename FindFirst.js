/**
 * FindFirst is my verion of combination of Linux grep and head command
 * node FindFirst.js <PATTERN> <FILENAME> [NUMBEROFLINES]
 * 
 */

const fs = require('fs');
const path = require('path');

if (process.argv.length !== 5) {
  console.log('Missing Argument');
  console.log(`Usage: node ${path.basename(process.argv[1])} <PATTERN><FILENAME> [NUMBEROFLINES]`);
  return;
}



let filename = process.argv[3];
let pattern = process.argv[2];
let numberOfLines = process.argv[4];

let content = fs.readFileSync(filename, 'utf-8');

let lines = content.split('\n');
for (let i=0; i < numberOfLines; i++) {
  if (lines[i].includes(pattern)) {
    console.log(lines[1]);
  }
}



