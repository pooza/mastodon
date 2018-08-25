import React from 'react';
import Immutable from 'immutable';
import PropTypes from 'prop-types';
import ImmutablePropTypes from 'react-immutable-proptypes';
import { Link } from 'react-router-dom';

const announcements = Immutable.fromJS([
  {
    body: '当インスタンスの使い方などはこちら',
    links: [
      { href: 'https://crowi.precure.fun/mstdn.precure', body: 'Ｗｉｋｉ' }
    ]
  },
  {
    body: '投稿についてのお願い',
    links: [
      { href: 'https://crowi.precure.fun/mstdn.precure/%E6%8A%95%E7%A8%BF%E3%81%AB%E3%81%A4%E3%81%84%E3%81%A6', body: '投稿について' }
    ]
  },
  {
    body: '重要なお知らせはインフォメーションアカウントを確認してください',
    links: [
      { href: 'https://precure.ml/@infomation', body: 'キュアスタ！お知らせアカウント'}
    ]
  }
]);

export default class Announcements extends React.PureComponent {

  static propTypes = {
    visible: PropTypes.bool.isRequired,
    onToggle: PropTypes.func.isRequired,
  }

  render () {
    const { visible, onToggle } = this.props;
    const caretClass = visible ? 'fa fa-caret-down' : 'fa fa-caret-up';
    return (
      <div className='announcements'>
        <div className='compose__extra__header'>
          <i className='fa fa-link' />
          おしらせ＆関連リンク
          <button className='compose__extra__header__icon' onClick={onToggle} >
            <i className={caretClass} />
          </button>
        </div>
        { visible && (
          <ul>
            {announcements.map((announcement, idx) => (
              <li key={idx}>
                <div className='announcements__icon'>
                  <i className='fa fa-bookmark' />
                </div>
                <div className='announcements__body'>
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
