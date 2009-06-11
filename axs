#!/usr/bin/python


"""Searches the index created by apt-xapian-index.

Xapian (supposedly) does a very good job of figuring out what you want (unlike
apt-cache search).  This script uses that power to find programs in the apt
database.
"""

from itertools import izip
from optparse import OptionParser
from traceback import print_exc
from subprocess import Popen, PIPE
import sys

import pyleif
from pyleif.lazy_regex import LazyRegex
import xapian


_OPTS = [(['-n', '--limit'], {'dest': 'limit',
                              'type': 'int',
                              'action': 'store',
                              'help': ('Maximum number of elements to display '
                                       '(default: %default)'),
                              'metavar': 'NUM'},
          5),
         (['-L', '--long'], {'dest': 'long',
                             'action': 'store_true',
                             'help': 'Show long descriptions (default: 3 lines)'},
          False),
         (['-i', '--index'], {'dest': 'index',
                              'type': 'string',
                              'action': 'store',
                              'help': 'Xapian index to parse (leave this alone)',
                              'metavar': 'FILE'},
          '/var/lib/apt-xapian-index/index'),
         (['-d', '--debug'], {'dest': 'debug',
                              'action': 'count',
                              'help': 'Increase debugging level'},
          0)]


def parse_opts():
    parser = OptionParser(usage='%prog [options] <query>',
                          description=__doc__)
    for optstrs, optopts, default in _OPTS:
        parser.add_option(*optstrs, **optopts)
        parser.set_defaults(**{optopts['dest']: default})
    options, args = parser.parse_args()
    if not args:
        parser.error('Must provide a query.')

    return options, args


def _word_length(word):
    return len(word) + 1 + word.endswith('.')


def reformat(par, length, height):
    """Reformats a paragraph to fit a given line length."""

    buf = []
    lines = len(par)
    idx = 0
    while idx < lines and (height is None or idx < height):
        buf.extend(par[idx].split())
        words = []
        if idx > 0:
            words.append('')
        curlen = 0
        while buf:
            word = buf[0]
            curlen += _word_length(word)
            if height is not None and idx == height - 1:
                if curlen + 3 > length:
                    break
            else:
                if curlen > length:
                    break
            buf.pop(0)
            words.append(word)
            if word == '.':
                break
            elif word.endswith('.'):
                words.append('')
        if height is not None and idx == height - 1 and words[-1]:
            words.append('...')
        par[idx] = ' '.join(words).rstrip()
        idx += 1

    while buf and (height is None or idx < height):
        words = []
        curlen = 0
        while curlen < length and buf:
            word = buf[0]
            curlen += _word_length(word)
            if height is not None and idx == height - 1:
                if curlen + 3 > length:
                    break
            else:
                if curlen > length:
                    break
            buf.pop(0)
            words.append(word)
            if word == '.':
                words.append('\n')
                break
            elif word.endswith('.'):
                words.append('')
        if height is not None and idx == height - 1 and words[-1]:
            words.append('...')
        par.append(' '.join(words).rstrip())
        idx += 1

    if height is not None:
        del par[height:]


def main(argv):
    (options, args) = parse_opts()

    database = xapian.Database(options.index)
    enquire = xapian.Enquire(database)

    qp = xapian.QueryParser()
    qp.set_stemmer(xapian.Stem('english'))
    qp.set_database(database)
    qp.set_stemming_strategy(xapian.QueryParser.STEM_SOME)
    query = qp.parse_query(' '.join(args))

    enquire.set_query(query)
    matches = enquire.get_mset(0, options.limit)

    result_strings = []
    description_pars = []
    desc_re = LazyRegex('^Description:')
    undesc_re = LazyRegex('^[A-Za-z]+:')
    for m in matches:
        data = m.document.get_data()
        result = '%3d: %s %s[%3d%%]' % (m.rank + 1,
                                        data,
                                        ''.join([' '] * (68 - len(data))),
                                        m.percent)
        result_strings.append(result)
        aps = Popen(['apt-cache', 'show', data], stdout=PIPE)
        (out, err) = aps.communicate()

        is_desc = False
        description = []
        for line in out.split('\n'):
            if not is_desc:
                if desc_re.match(line):
                    is_desc = True
                    description.append(line)
            else:
                if undesc_re.match(line):
                    break
                description.append(line)

        description_pars.append(description)

    desc_len = None if options.long else 3
    for desc in description_pars:
        reformat(desc, 74, desc_len)

    print '%d results found.' % matches.get_matches_estimated()
    print 'Results 1-%d:' % matches.size()

    for res, desc in izip(result_strings, description_pars):
        print res
        for line in desc:
            print '    ', line

    return 0


if __name__ == '__main__':
    try:
        ret = main(sys.argv)
    except Exception:
        print >> sys.stderr, 'Exception occurred'
        print_exc(file=sys.stderr)
        sys.exit(255)
    else:
        sys.exit(ret)
