import React from 'react';
import Immutable from 'immutable';
import PropTypes from 'prop-types';
import ImmutablePropTypes from 'react-immutable-proptypes';
import { Link } from 'react-router-dom';

const links = Immutable.fromJS([
  {
    body: 'お知らせ',
    links: [
      {href: 'https://mstdn.delmulin.com/@info', body: 'お知らせボット'},
      {href: 'https://blog.delmulin.com/categories/お知らせ', body: '過去のお知らせ'},
    ],
  },
  {
    body: 'デルムリン丼Blog',
    links: [
      {href: 'https://blog.delmulin.com/', body: 'Home'},
      {href: 'https://blog.delmulin.com/categories/新規さん向け', body: '新規さん向け'},
      {href: 'https://blog.delmulin.com/articles/実況', body: '実況'},
      {href: 'https://blog.delmulin.com/articles/魂の絆', body: '「魂の絆」画像等の著作権'},
    ],
  },
  {
    body: 'モロヘイヤ',
    links: [
      {href: '/mulukhiya', body: 'Home'},
      {href: '/mulukhiya/app/status', body: '投稿'},
      {href: '/mulukhiya/app/media', body: 'メディア'},
      {href: '/mulukhiya/app/config', body: '設定'},
      {href: '/mulukhiya/app/api', body: 'API'},
    ],
  },
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
          デルムリン丼関連リンク
          <button className='compose__extra__header__icon' onClick={onToggle} >
            <i className={caretClass} />
          </button>
        </div>
        { visible && (
          <ul>
            {links.map((entry, idx) => (
              <li key={idx}>
                <div className='relative_links__icon'>
                  <i className='fa fa-bookmark' />
                </div>
                <div className='relative_links__body'>
                  <p>{entry.get('body')}</p>
                  <div className='links'>
                    {entry.get('links').map((link, i) => (
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
