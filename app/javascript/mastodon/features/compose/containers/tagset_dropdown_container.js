import { connect } from 'react-redux';

import { changeTagset } from '../../../actions/compose';
import { openModal, closeModal } from '../../../actions/modal';
import { isUserTouching } from '../../../is_mobile';
import TagsetDropdown from '../components/tagset_dropdown';

const mapStateToProps = state => ({
  value: state.getIn(['compose', 'tagset']),
});

const mapDispatchToProps = dispatch => ({

  onChange (value) {
    dispatch(changeTagset(value));
  },

  isUserTouching,
  onModalOpen: props => dispatch(openModal({
    modalType: 'ACTIONS',
    modalProps: props,
  })),
  onModalClose: () => dispatch(closeModal({
    modalType: undefined,
    ignoreFocus: false,
  })),

});

export default connect(mapStateToProps, mapDispatchToProps)(TagsetDropdown);
