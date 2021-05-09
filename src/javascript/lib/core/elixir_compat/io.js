
function puts(args) {
    console.log(args)
    return Symbol.for('ok');
}

function inspect(args) {
    console.log(args)
    return args;
}

export default {
    puts,
    inspect
}