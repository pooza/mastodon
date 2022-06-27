import React from 'react';
import Immutable from 'immutable';
import PropTypes from 'prop-types';
import ImmutablePropTypes from 'react-immutable-proptypes';
import { Link } from 'react-router-dom';

const request = new XMLHttpRequest();
request.open('GET', '/links.json', false);
request.send(null);
const links = Immutable.fromJS(JSON.parse(request.responseText));

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
          キュアスタ！関連リンク
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
