import PropTypes from 'prop-types';
import { PureComponent } from 'react';

import { injectIntl, defineMessages } from 'react-intl';

import classNames from 'classnames';

import { supportsPassiveEvents } from 'detect-passive-events';
import Overlay from 'react-overlays/Overlay';

import { Icon }  from 'mastodon/components/icon';

import { IconButton } from '../../../components/icon_button';

const messages = defineMessages({
  empty_short: { id: 'tagset.empty.short', defaultMessage: 'Empty' },
  empty_long: { id: 'tagset.empty.long', defaultMessage: 'Empty tagset' },
  episodes_short: { id: 'tagset.episodes.short', defaultMessage: 'Other episodes' },
  episodes_long: { id: 'tagset.episodes.long', defaultMessage: 'Episode browser of Mulukhiya' },
  hide_livecure: { id: 'tagset.hide_livecure', defaultMessage: 'Hide livecures' },
  show_livecure: { id: 'tagset.show_livecure', defaultMessage: 'Show livecures' },
  change: { id: 'tagset.change', defaultMessage: 'Change tagset' },
});

const listenerOptions = supportsPassiveEvents ? { passive: true, capture: true } : true;

class TagsetDropdownMenu extends PureComponent {

  static propTypes = {
    style: PropTypes.object,
    items: PropTypes.array.isRequired,
    value: PropTypes.string.isRequired,
    onClose: PropTypes.func.isRequired,
    onChange: PropTypes.func.isRequired,
  };

  handleDocumentClick = e => {
    if (this.node && !this.node.contains(e.target)) {
      this.props.onClose();
      e.stopPropagation();
    }
  };

  handleKeyDown = e => {
    const { items } = this.props;
    const value = e.currentTarget.getAttribute('data-index');
    const index = items.findIndex(item => {
      return (item.value === value);
    });
    let element = null;

    switch(e.key) {
    case 'Escape':
      this.props.onClose();
      break;
    case 'Enter':
      this.handleClick(e);
      break;
    case 'ArrowDown':
      element = this.node.childNodes[index + 1] || this.node.firstChild;
      break;
    case 'ArrowUp':
      element = this.node.childNodes[index - 1] || this.node.lastChild;
      break;
    case 'Tab':
      if (e.shiftKey) {
        element = this.node.childNodes[index - 1] || this.node.lastChild;
      } else {
        element = this.node.childNodes[index + 1] || this.node.firstChild;
      }
      break;
    case 'Home':
      element = this.node.firstChild;
      break;
    case 'End':
      element = this.node.lastChild;
      break;
    }

    if (element) {
      element.focus();
      this.props.onChange(element.getAttribute('data-index'));
      e.preventDefault();
      e.stopPropagation();
    }
  };

  handleClick = e => {
    const value = e.currentTarget.getAttribute('data-index');

    e.preventDefault();

    this.props.onClose();
    this.props.onChange(value);
  };

  componentDidMount () {
    document.addEventListener('click', this.handleDocumentClick, { capture: true });
    document.addEventListener('touchend', this.handleDocumentClick, listenerOptions);
    if (this.focusedItem) this.focusedItem.focus({ preventScroll: true });
  }

  componentWillUnmount () {
    document.removeEventListener('click', this.handleDocumentClick, { capture: true });
    document.removeEventListener('touchend', this.handleDocumentClick, listenerOptions);
  }

  setRef = c => {
    this.node = c;
  };

  setFocusRef = c => {
    this.focusedItem = c;
  };

  render () {
    const { style, items, value } = this.props;

    return (
      <div style={{ ...style }} role='listbox' ref={this.setRef}>
        {items.map(item => (
          <div role='option' tabIndex={0} key={item.value} data-index={item.value} onKeyDown={this.handleKeyDown} onClick={this.handleClick} className={classNames('privacy-dropdown__option', { active: item.value === value })} aria-selected={item.value === value} ref={item.value === value ? this.setFocusRef : null}>
            <div className='privacy-dropdown__option__icon'>
              <Icon id={item.icon} fixedWidth />
            </div>

            <div className='privacy-dropdown__option__content'>
              <strong>{item.text}</strong>
              {item.meta}
            </div>
          </div>
        ))}
      </div>
    );
  }

}

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
    if (this.props.isUserTouching && this.props.isUserTouching()) {
      if (this.state.open) {
        this.props.onModalClose();
      } else {
        this.props.onModalOpen({
          actions: this.options.map(option => ({ ...option, active: option.value === this.props.value })),
          onClick: this.handleModalActionClick,
        });
      }
    } else {
      if (this.state.open && this.activeElement) {
        this.activeElement.focus({ preventScroll: true });
      }
      this.setState({ open: !this.state.open });
    }
  };

  handleModalActionClick = (e) => {
    e.preventDefault();

    const { value } = this.options[e.currentTarget.getAttribute('data-index')];

    this.props.onModalClose();
    this.props.onChange(value);
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
    this.props.onChange(value);
  };

  UNSAFE_componentWillMount () {
    const { intl: { formatMessage } } = this.props;

    this.options = [
      { icon: 'hashtag', value: 'empty', text: formatMessage(messages.empty_short), meta: formatMessage(messages.empty_long) },
    ];

    const request = new XMLHttpRequest();
    request.open('GET', '/mulukhiya/api/program', false);
    request.send(null);
    if (request.status != 200) {return}
    const result = JSON.parse(request.responseText);
    for (const k of Object.keys(result)) {
      const v = result[k];
      if (!v.enable) {continue}
      const text = `「${v.series}」用タグセット`;
      const meta = [];
      if (v.episode) {meta.push(`${v.episode}${v.episode_suffix || '話'}`)}
      if (v.subtitle) {meta.push(`「${v.subtitle}」`)}
      if (v.air) {meta.push('エア番組')}
      if (v.livecure) {meta.push('実況')}
      if (v.minutes) {meta.push(`(${v.minutes}分)`)}
      v.extra_tags.map(tag => {meta.push(tag)});
      this.options.push({icon: 'hashtag', value: k, text: text, meta: meta.join(' ')});
    }

    this.options.push({ icon: 'film', value: 'episodes', text: formatMessage(messages.episodes_short), meta: formatMessage(messages.episodes_long) });
    this.options.push({ icon: 'microphone-slash', value: 'hide_livecure', text: formatMessage(messages.hide_livecure) });
    this.options.push({ icon: 'microphone', value: 'show_livecure', text: formatMessage(messages.show_livecure) });
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
      <div className={classNames('privacy-dropdown', placement, { active: open })} onKeyDown={this.handleKeyDown}>
        <div className={classNames('privacy-dropdown__value', { active: this.options.indexOf(valueOption) === (placement === 'bottom' ? 0 : (this.options.length - 1)) })} ref={this.setTargetRef}>
          <IconButton
            className='privacy-dropdown__value-icon'
            icon={valueOption.icon}
            title={intl.formatMessage(messages.change_tagset)}
            size={18}
            expanded={open}
            active={open}
            inverted
            onClick={this.handleToggle}
            onMouseDown={this.handleMouseDown}
            onKeyDown={this.handleButtonKeyDown}
            style={{ height: null, lineHeight: '27px' }}
            disabled={disabled}
          />
        </div>

        <Overlay show={open} placement={'bottom'} flip target={this.findTarget} container={container} popperConfig={{ strategy: 'fixed', onFirstUpdate: this.handleOverlayEnter }}>
          {({ props, placement }) => (
            <div {...props}>
              <div className={`dropdown-animation privacy-dropdown__dropdown ${placement}`}>
                <TagsetDropdownMenu
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
