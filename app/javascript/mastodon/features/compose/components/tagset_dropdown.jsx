import PropTypes from 'prop-types';
import { PureComponent } from 'react';

import { injectIntl, defineMessages } from 'react-intl';

import classNames from 'classnames';

import Overlay from 'react-overlays/Overlay';

import TagIcon from '@/material-icons/400-24px/tag.svg?react';
import CancelIcon from '@/material-icons/400-24px/cancel.svg?react';
import MovieIcon from '@/material-icons/400-24px/movie.svg?react';
import RefreshIcon from '@/material-icons/400-24px/refresh.svg?react';
import { DropdownSelector } from 'mastodon/components/dropdown_selector';
import { Icon }  from 'mastodon/components/icon';

const messages = defineMessages({
  empty_short: { id: 'tagset.empty.short', defaultMessage: 'Empty' },
  empty_long: { id: 'tagset.empty.long', defaultMessage: 'Empty tagset' },
  episodes_short: { id: 'tagset.episodes.short', defaultMessage: 'Other episodes' },
  episodes_long: { id: 'tagset.episodes.long', defaultMessage: 'Episode browser of Mulukhiya' },
  reload_short: { id: 'tagset.reload.short', defaultMessage: 'Reload' },
  reload_long: { id: 'tagset.reload.long', defaultMessage: 'Reload episodes' },
  change: { id: 'tagset.change', defaultMessage: 'Change tagset' },
  label: { id: 'tagset.label', defaultMessage: 'Livecure' },
});

class TagsetDropdown extends PureComponent {

  static propTypes = {
    isUserTouching: PropTypes.func,
    onModalOpen: PropTypes.func,
    onModalClose: PropTypes.func,
    value: PropTypes.string.isRequired,
    onChange: PropTypes.func.isRequired,
    noDirect: PropTypes.bool,
    container: PropTypes.func,
    disabled: PropTypes.bool,
    intl: PropTypes.object.isRequired,
  };

  state = {
    open: false,
    placement: 'bottom',
  };

  handleToggle = () => {
    if (this.state.open && this.activeElement) {
      this.activeElement.focus({ preventScroll: true });
    }

    this.setState({ open: !this.state.open });
  };

  handleKeyDown = e => {
    switch(e.key) {
    case 'Escape':
      this.handleClose();
      break;
    }
  };

  handleMouseDown = () => {
    if (!this.state.open) {
      this.activeElement = document.activeElement;
    }
  };

  handleButtonKeyDown = (e) => {
    switch(e.key) {
    case ' ':
    case 'Enter':
      this.handleMouseDown();
      break;
    }
  };

  handleClose = () => {
    if (this.state.open && this.activeElement) {
      this.activeElement.focus({ preventScroll: true });
    }
    this.setState({ open: false });
  };

  handleChange = value => {
    if (value == 'reload') {
      UNSAFE_componentWillMount();
      return;
    }
    this.props.onChange(value);
  };

  UNSAFE_componentWillMount () {
    const { intl: { formatMessage } } = this.props;

    this.options = [
      { value: 'empty', icon: 'cancel', iconComponent: CancelIcon, text: formatMessage(messages.empty_short), meta: formatMessage(messages.empty_long) },
    ];

    fetch('/mulukhiya/api/program')
      .then(response => response.json())
      .then(result => {
        for (const k of Object.keys(result)) {
          const v = result[k];
          if (!v.enable) continue;
          const text = `「${v.series}」用タグセット`;
          const meta = [];
          if (v.episode) meta.push(`${v.episode}${v.episode_suffix || '話'}`);
          if (v.subtitle) meta.push(`「${v.subtitle}」`);
          if (v.air) meta.push('エア番組');
          if (v.livecure) meta.push('実況');
          if (v.minutes) meta.push(`(${v.minutes}分)`);
          v.extra_tags.map(tag => {meta.push(tag)});
          this.options.push({value: k, icon: 'tag' , iconComponent: TagIcon, text: text, meta: meta.join(' ')});
        }
      }).then(_ => {
        this.options.push({ value: 'episodes', icon: 'movie', iconComponent: MovieIcon, text: formatMessage(messages.episodes_short), meta: formatMessage(messages.episodes_long) });
        this.options.push({ value: 'reload', icon: 'refresh', iconComponent: RefreshIcon, text: formatMessage(messages.reload_short), meta: formatMessage(messages.reload_long) });
      })
  }

  setTargetRef = c => {
    this.target = c;
  };

  findTarget = () => {
    return this.target;
  };

  handleOverlayEnter = (state) => {
    this.setState({ placement: state.placement });
  };

  render () {
    const { value, container, disabled, intl } = this.props;
    const { open, placement } = this.state;

    const valueOption = this.options.find(item => item.value === value);

    return (
      <div ref={this.setTargetRef} onKeyDown={this.handleKeyDown}>
        <button
          type='button'
          title={intl.formatMessage(messages.change)}
          aria-expanded={open}
          onClick={this.handleToggle}
          onMouseDown={this.handleMouseDown}
          onKeyDown={this.handleButtonKeyDown}
          disabled={disabled}
          className={classNames('dropdown-button', { active: open })}
        >
          <Icon id='tag' icon={TagIcon} />
          <span className='dropdown-button__label'>{intl.formatMessage(messages.label)}</span>
        </button>

        <Overlay show={open} offset={[5, 5]} placement={placement} flip target={this.findTarget} container={container} popperConfig={{ strategy: 'fixed', onFirstUpdate: this.handleOverlayEnter }}>
          {({ props, placement }) => (
            <div {...props}>
              <div className={`dropdown-animation tagset-dropdown__dropdown ${placement}`}>
                <DropdownSelector
                  items={this.options}
                  value={value}
                  onClose={this.handleClose}
                  onChange={this.handleChange}
                />
              </div>
            </div>
          )}
        </Overlay>
      </div>
    );
  }

}

export default injectIntl(TagsetDropdown);
