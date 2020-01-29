import React from 'react';
import Immutable from 'immutable';
import PropTypes from 'prop-types';
import ImmutablePropTypes from 'react-immutable-proptypes';
import { Link } from 'react-router-dom';

const relative_links = Immutable.fromJS([
  {
    body: 'キュアスタ！Wiki',
    links: [
      {href: 'https://growi.b-shock.org/curesta', body: 'Wikiトップ' },
      {href: 'https://growi.b-shock.org/curesta/新規さん向け', body: '新規さん向け'},
      {href: 'https://growi.b-shock.org/curesta/イベント/実況', body: '実況'}
    ]
  },
  {
    body: 'お知らせ',
    links: [
      {href: 'https://precure.ml/@infomation', body: 'お知らせアカウント'},
      {href: 'https://growi.b-shock.org/curesta/過去のお知らせ', body: '過去のお知らせ'}
    ]
  }
]);

export default class RelativeLinks extends React.PureComponent {
  static propTypes = {
    visible: PropTypes.bool.isRequired,
    onToggle: PropTypes.func.isRequired,
  }

  render () {
    const { visible, onToggle } = this.props;
    const caretClass = visible ? 'fa fa-caret-down' : 'fa fa-caret-up';
    return (
      <div className='relative_links'>
        <div className='compose__extra__header'>
          <i className='fa fa-link' />
          お知らせ＆関連リンク
          <button className='compose__extra__header__icon' onClick={onToggle} >
            <i className={caretClass} />
          </button>
        </div>
        { visible && (
          <ul>
            {relative_links.map((announcement, idx) => (
              <li key={idx}>
                <div className='relative_links__icon'>
                  <i className='fa fa-bookmark' />
                </div>
                <div className='relative_links__body'>
                  <p>{announcement.get('body')}</p>
                  <div className='links'>
                    {announcement.get('links').map((link, i) => (
                      link.get('link') === true
                      ? <Link to={link.get('href')}>
                          {link.get('body')}
                        </Link>
                      : <a href={link.get('href')} target='_blank' key={i}>
                          {link.get('body')}
                        </a>
                    ))}
                  </div>
                </div>
              </li>
            ))}
          </ul>
        )}
      </div>
    );
  }
}
