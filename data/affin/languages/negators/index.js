module.exports = {
    negators: require('./all.json'),
    defaultCoeff: 1,
    find: function(word, lang) {
        for (var i in this.negators[lang]) {
            if (this.negators[lang][i] === word) {
                return true;
            }
        }
        return false;
    }
};
